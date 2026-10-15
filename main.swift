// Copyright 2026 pauloipf
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Virtualization
import AppKit

// Uso: veja `usage` mais abaixo, ou rode ./arm64vm --help

func fatal(_ message: String) -> Never {
    print(message)
    exit(1)
}

// Valor que vem logo após uma opção (ex.: --vm ubuntu), ignorando outras opções
func argValue(after option: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: option), index + 1 < args.count, !args[index + 1].hasPrefix("--") else {
        return nil
    }
    return args[index + 1]
}

// Arquivos ficam na mesma pasta do executável, independente de onde ele é chamado
let baseDirectory = Bundle.main.executableURL!.deletingLastPathComponent()
let vmsDirectory = baseDirectory.appendingPathComponent("vms")

let gigabyte: UInt64 = 1 << 30
let hostCPUs = ProcessInfo.processInfo.processorCount
let hostMemory = ProcessInfo.processInfo.physicalMemory

// Núcleos e RAM de cada VM, salvos em vms/<nome>/config.json.
// Podem mudar entre um boot e outro sem afetar o sistema instalado.
struct VMSettings: Codable {
    var cpus: Int
    var memoryGB: UInt64

    static let defaults = VMSettings(cpus: max(2, min(4, hostCPUs - 2)), memoryGB: 4)

    static func url(for vmName: String) -> URL {
        vmsDirectory.appendingPathComponent(vmName).appendingPathComponent("config.json")
    }

    static func load(for vmName: String) -> VMSettings {
        guard let data = try? Data(contentsOf: url(for: vmName)),
              let settings = try? JSONDecoder().decode(VMSettings.self, from: data) else {
            return defaults
        }
        return settings
    }

    func save(for vmName: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(self).write(to: VMSettings.url(for: vmName))
        } catch {
            fatal("Erro ao salvar config.json: \(error)")
        }
    }

    func validate() {
        let maxCPUs = min(hostCPUs, VZVirtualMachineConfiguration.maximumAllowedCPUCount)
        guard cpus >= VZVirtualMachineConfiguration.minimumAllowedCPUCount, cpus <= maxCPUs else {
            fatal("Núcleos inválidos: \(cpus). Use de \(VZVirtualMachineConfiguration.minimumAllowedCPUCount) a \(maxCPUs).")
        }
        // Deixa ao menos 2 GB para o macOS
        let maxGB = min(hostMemory, VZVirtualMachineConfiguration.maximumAllowedMemorySize) / gigabyte - 2
        guard memoryGB >= 1, memoryGB <= maxGB else {
            fatal("Memória inválida: \(memoryGB) GB. Use de 1 a \(maxGB) GB.")
        }
    }
}

func existingVMs() -> [String] {
    let dirs = (try? FileManager.default.contentsOfDirectory(at: vmsDirectory, includingPropertiesForKeys: nil)) ?? []
    return dirs.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("disk.img").path) }
        .map { $0.lastPathComponent }
        .sorted()
}

func listVMs() {
    let vms = existingVMs()
    guard !vms.isEmpty else {
        print("Nenhuma VM em \(vmsDirectory.path)")
        return
    }
    let width = vms.map { $0.count }.max() ?? 0
    for name in vms {
        let diskURL = vmsDirectory.appendingPathComponent(name).appendingPathComponent("disk.img")
        let values = try? diskURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        let gb = { (bytes: Int?) in String(format: "%.1f GB", Double(bytes ?? 0) / 1_073_741_824) }
        let settings = VMSettings.load(for: name)
        let paddedName = name.padding(toLength: width, withPad: " ", startingAt: 0)
        print("▸ \(paddedName)   \(settings.cpus) núcleos, \(settings.memoryGB) GB RAM, disco: \(gb(values?.fileSize)) (em uso: \(gb(values?.totalFileAllocatedSize)))")
    }
}

// Tamanho no formato 64g, 512m ou bytes
func parseSize(_ text: String) -> UInt64? {
    let lower = text.lowercased()
    let units: [Character: UInt64] = ["k": 1 << 10, "m": 1 << 20, "g": 1 << 30, "t": 1 << 40]
    if let last = lower.last, let multiplier = units[last] {
        return UInt64(lower.dropLast()).map { $0 * multiplier }
    }
    return UInt64(lower)
}

// Cria um disco esparso (equivalente a mkfile -n): ocupa só o espaço que o sistema convidado usar
func createDisk(at url: URL, size: UInt64) {
    guard !FileManager.default.fileExists(atPath: url.path) else {
        fatal("\(url.path) já existe. Para recriar a VM, apague a pasta dela antes.")
    }
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: size)
        try handle.close()
    } catch {
        fatal("Erro ao criar o disco: \(error)")
    }
    print("Disco criado: \(url.path) (\(size / (1 << 30)) GB)")
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, VZVirtualMachineDelegate {
    var window: NSWindow!
    var vmView: VZVirtualMachineView!
    var virtualMachine: VZVirtualMachine!
    var stopRequested = false

    let vmName: String
    let vmDirectory: URL
    let settings: VMSettings
    let installMode = CommandLine.arguments.contains("--install")

    init(vmName: String, settings: VMSettings) {
        self.vmName = vmName
        self.vmDirectory = vmsDirectory.appendingPathComponent(vmName)
        self.settings = settings
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = VZVirtualMachineConfiguration()
        config.cpuCount = settings.cpus
        config.memorySize = settings.memoryGB * gigabyte

        let bootloader = VZEFIBootLoader()
        let variableStoreURL = vmDirectory.appendingPathComponent("efi_variables")

        do {
            if FileManager.default.fileExists(atPath: variableStoreURL.path) {
                bootloader.variableStore = VZEFIVariableStore(url: variableStoreURL)
            } else {
                bootloader.variableStore = try VZEFIVariableStore(creatingVariableStoreAt: variableStoreURL, options: [])
            }
        } catch {
            fatal("Erro no bootloader: \(error)")
        }
        config.bootLoader = bootloader

        do {
            let diskURL = vmDirectory.appendingPathComponent("disk.img")
            let diskAttachment = try VZDiskImageStorageDeviceAttachment(url: diskURL, readOnly: false)
            config.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: diskAttachment)]

            // A ISO só é anexada no modo de instalação, para não voltar ao instalador depois
            if installMode {
                let isoURL = findInstallerISO()
                let isoAttachment = try VZDiskImageStorageDeviceAttachment(url: isoURL, readOnly: true)
                config.storageDevices.append(VZUSBMassStorageDeviceConfiguration(attachment: isoAttachment))
                print("Modo de instalação: ISO anexada (\(isoURL.lastPathComponent)).")
            }
        } catch {
            fatal("Erro no armazenamento: \(error)")
        }

        let networkDevice = VZVirtioNetworkDeviceConfiguration()
        networkDevice.attachment = VZNATNetworkDeviceAttachment()
        config.networkDevices = [networkDevice]

        let graphicsDevice = VZVirtioGraphicsDeviceConfiguration()
        graphicsDevice.scanouts = [
            VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1920, heightInPixels: 1080)
        ]
        config.graphicsDevices = [graphicsDevice]

        // Teclado e mouse: sem config.keyboards a VM não recebe nenhuma tecla
        config.keyboards = [VZUSBKeyboardConfiguration()]
        config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

        // Áudio (somente saída)
        let soundDevice = VZVirtioSoundDeviceConfiguration()
        let outputStream = VZVirtioSoundDeviceOutputStreamConfiguration()
        outputStream.sink = VZHostAudioOutputStreamSink()
        soundDevice.streams = [outputStream]
        config.audioDevices = [soundDevice]

        // Pasta compartilhada: vms/<nome>/compartilhado <-> tag "compartilhado" no sistema convidado
        let sharedURL = vmDirectory.appendingPathComponent("compartilhado")
        try? FileManager.default.createDirectory(at: sharedURL, withIntermediateDirectories: true)
        let sharedDirectory = VZSharedDirectory(url: sharedURL, readOnly: false)
        let fileSystemDevice = VZVirtioFileSystemDeviceConfiguration(tag: "compartilhado")
        fileSystemDevice.share = VZSingleDirectoryShare(directory: sharedDirectory)
        config.directorySharingDevices = [fileSystemDevice]

        config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        config.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]

        do {
            try config.validate()
        } catch {
            fatal("Configuração inválida: \(error)")
        }

        virtualMachine = VZVirtualMachine(configuration: config)
        virtualMachine.delegate = self

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 750),
            styleMask: [.closable, .miniaturizable, .titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = installMode ? "\(vmName) - Instalação" : vmName
        window.delegate = self
        window.center()

        vmView = VZVirtualMachineView()
        vmView.virtualMachine = virtualMachine
        vmView.capturesSystemKeys = true
        vmView.automaticallyReconfiguresDisplay = true
        window.contentView = vmView
        window.makeKeyAndOrderFront(nil)
        // A view precisa ser o first responder para receber o teclado
        window.makeFirstResponder(vmView)
        NSApp.activate(ignoringOtherApps: true)

        virtualMachine.start { result in
            switch result {
            case .success():
                print("Máquina Virtual iniciada com sucesso!")
            case .failure(let error):
                fatal("Erro ao iniciar a VM: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Desligamento limpo

    // Fechar a janela envia um pedido de desligamento (ACPI) ao sistema convidado em vez de matar a VM
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let vm = virtualMachine, vm.state == .running || vm.state == .paused else {
            return true
        }

        if !stopRequested && vm.canRequestStop {
            do {
                try vm.requestStop()
                stopRequested = true
                window.title = "\(vmName) - Desligando..."
                return false
            } catch {
                print("Falha ao solicitar desligamento: \(error.localizedDescription)")
            }
        }

        let alert = NSAlert()
        alert.messageText = "A VM \(vmName) ainda não desligou."
        alert.informativeText = "Forçar o desligamento equivale a tirar a máquina da tomada e pode corromper dados não salvos."
        alert.addButton(withTitle: "Aguardar")
        alert.addButton(withTitle: "Forçar desligamento")
        alert.beginSheetModal(for: window) { response in
            if response == .alertSecondButtonReturn {
                vm.stop { _ in NSApp.terminate(nil) }
            }
        }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Cmd+Q passa pelo mesmo fluxo de fechar a janela
        if let vm = virtualMachine, vm.state == .running || vm.state == .paused {
            _ = windowShouldClose(window)
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        print("A VM \(vmName) foi desligada.")
        NSApp.terminate(nil)
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        print("A VM parou com erro: \(error.localizedDescription)")
        NSApp.terminate(nil)
    }

    // ISO passada após --install (caminho absoluto ou relativo à pasta da VM);
    // sem argumento, usa a única .iso existente na pasta da VM
    func findInstallerISO() -> URL {
        if let path = argValue(after: "--install") {
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : vmDirectory.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                fatal("ISO não encontrada: \(url.path)")
            }
            return url
        }

        let files = (try? FileManager.default.contentsOfDirectory(at: vmDirectory, includingPropertiesForKeys: nil)) ?? []
        let isos = files.filter { $0.pathExtension.lowercased() == "iso" }
        switch isos.count {
        case 1:
            return isos[0]
        case 0:
            fatal("Nenhuma .iso encontrada em \(vmDirectory.path)")
        default:
            let names = isos.map { $0.lastPathComponent }.sorted().joined(separator: "\n  ")
            fatal("Mais de uma .iso na pasta. Escolha uma: ./arm64vm --vm \(vmName) --install <arquivo.iso>\n  \(names)")
        }
    }
}

func buildMainMenu() -> NSMenu {
    let mainMenu = NSMenu()
    let appItem = NSMenuItem()
    mainMenu.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Desligar VM", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    return mainMenu
}

let usage = """
Uso: ./arm64vm [--vm <nome>] [opções]

Cada VM fica em vms/<nome>/. Sem --vm, usa a única VM existente.

  --vm <nome>            VM a iniciar ou criar
  --new <tamanho>        cria a VM com um disco esparso novo (ex.: 64g)
  --install [arq.iso]    anexa a ISO de instalação (a única .iso da pasta da VM, ou a indicada)
  --cpus <n>             núcleos da VM (fica salvo em vms/<nome>/config.json)
  --mem <tamanho>        RAM da VM em GB inteiros, ex.: 8g (fica salvo)
  --list                 lista as VMs
  -h, --help             mostra esta ajuda

Exemplos:
  ./arm64vm --vm ubuntu --new 64g --install
  ./arm64vm --vm ubuntu --cpus 6 --mem 8g
"""

if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print(usage)
    exit(0)
}

if CommandLine.arguments.contains("--list") {
    listVMs()
    exit(0)
}

let vmName: String
if let name = argValue(after: "--vm") {
    vmName = name
} else {
    let vms = existingVMs()
    guard vms.count == 1 else {
        let list = vms.isEmpty ? "nenhuma" : vms.joined(separator: ", ")
        fatal("Indique a VM com --vm <nome>. VMs existentes: \(list)")
    }
    vmName = vms[0]
}
guard vmName.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil, !vmName.hasPrefix(".") else {
    fatal("Nome de VM inválido: \(vmName) (use letras, números, ponto, _ ou -)")
}
let vmDiskURL = vmsDirectory.appendingPathComponent(vmName).appendingPathComponent("disk.img")

if CommandLine.arguments.contains("--new") {
    guard let sizeText = argValue(after: "--new"), let size = parseSize(sizeText), size >= 1 << 30 else {
        fatal("Informe o tamanho do disco com pelo menos 1g, ex.: --new 64g")
    }
    createDisk(at: vmDiskURL, size: size)
} else if !FileManager.default.fileExists(atPath: vmDiskURL.path) {
    let vms = existingVMs()
    let list = vms.isEmpty ? "nenhuma" : vms.joined(separator: ", ")
    fatal("VM \"\(vmName)\" não encontrada. VMs existentes: \(list)\nPara criar: ./arm64vm --vm \(vmName) --new 64g --install")
}

// --cpus e --mem alteram a configuração e ficam salvos para os próximos boots
var settings = VMSettings.load(for: vmName)
if CommandLine.arguments.contains("--cpus") {
    guard let text = argValue(after: "--cpus"), let cpus = Int(text) else {
        fatal("Informe o número de núcleos, ex.: --cpus 6")
    }
    settings.cpus = cpus
}
if CommandLine.arguments.contains("--mem") {
    guard let text = argValue(after: "--mem"), let bytes = parseSize(text.lowercased().hasSuffix("b") ? String(text.dropLast()) : text),
          bytes % gigabyte == 0 else {
        fatal("Informe a memória em GB inteiros, ex.: --mem 8g")
    }
    settings.memoryGB = bytes / gigabyte
}
settings.validate()
settings.save(for: vmName)
print("VM \(vmName): \(settings.cpus) núcleos, \(settings.memoryGB) GB de RAM")

let app = NSApplication.shared
// Executável sem bundle .app: sem isso o app não vira app "de primeiro plano"
// e o teclado continua indo para o Terminal
app.setActivationPolicy(.regular)
app.mainMenu = buildMainMenu()
let delegate = AppDelegate(vmName: vmName, settings: settings)
app.delegate = delegate
app.run()
