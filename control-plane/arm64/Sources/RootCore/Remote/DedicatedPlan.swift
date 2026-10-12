import Foundation

/// Level 2 on Linux: a user of its own (`metaservice`), the folder `/opt/metaservice` and one hardened systemd service. Needs admin rights (sudo).
/// Only adds: a user, a folder, a unit file. Nothing that exists is changed. The plan and its scripts are checked here; carrying it out as admin is not wired yet.
public enum DedicatedPlan {
    public static let user = "metaservice"
    public static let box = "/opt/metaservice"
    public static let service = "metaservice-agent"
    public static let unitFile = "/etc/systemd/system/metaservice-agent.service"
    private static let tasksLimit = 512

    public static func make(_ options: RemoteInstallOptions, agentSize: Int?) -> [PlannedStep] {
        [account(), folder(), agent(size: agentSize), enroll(options), unit(options), start()]
    }

    /// The service file. It writes only inside the box, cannot gain privileges, and has the allowance as a real memory cap.
    public static func unitText(_ options: RemoteInstallOptions) -> String {
        let command = ([box + "/bin/" + InstallPlan.programName] + PlanScripts.runArguments(options, box: box)).map(Shell.quote).joined(separator: " ")
        let memory = options.settings.ramAllowanceMb.map { "MemoryMax=\($0)M\n" } ?? ""
        return """
        [Unit]
        Description=MetaService Agent (made by the parent)
        After=network-online.target

        [Service]
        User=\(user)
        ExecStart=\(command)
        Restart=on-failure
        NoNewPrivileges=yes
        ProtectSystem=strict
        ProtectHome=yes
        PrivateTmp=yes
        ReadWritePaths=\(box)
        TasksMax=\(tasksLimit)
        \(memory)
        [Install]
        WantedBy=multi-user.target

        """
    }

    /// Refuses a computer that already has the user or the folder. Exit 20 means "already there".
    public static let beforeScript = """
    set -u
    if id -u \(user) >/dev/null 2>&1; then echo "ms-error: the user \(user) already exists, so nothing was changed"; exit 20; fi
    if [ -e \(box) ]; then echo "ms-error: \(box) already exists, so nothing was changed"; exit 20; fi
    if [ -e \(unitFile) ]; then echo "ms-error: the service file already exists, so nothing was changed"; exit 20; fi
    echo ok

    """

    /// Takes it away again: service, unit file, user, folder. It refuses a folder that has no MetaService record.
    public static let removeScript = """
    set -u
    if ! grep -q '"made_by":"\(PlanScripts.madeBy)"' \(box)/manifest.json 2>/dev/null; then echo "ms-error: that is not a MetaService box, so nothing was removed"; exit 30; fi
    systemctl disable --now \(service) 2>/dev/null || true
    rm -f \(unitFile)
    systemctl daemon-reload
    userdel \(user) 2>/dev/null || true
    rm -rf -- \(box)
    echo removed

    """

    // MARK: steps

    private static func account() -> PlannedStep {
        PlannedStep(id: "user", label: "Make the MetaService user", changes: ["Create the system user \(user): no password, no login shell, no sudo. It owns only \(box)."],
                    operations: [.runAsAdmin(command: "useradd --system --home-dir \(box) --no-create-home --shell /usr/sbin/nologin \(user)")])
    }

    private static func folder() -> PlannedStep {
        PlannedStep(id: "folder", label: "Make the box folder", changes: ["Create the folder \(box) (with bin, state and logs inside), owned by \(user). It is new."],
                    operations: [.runAsAdmin(command: "install -d -o \(user) -g \(user) -m 700 \(box) \(box)/bin \(box)/state \(box)/logs")])
    }

    private static func agent(size: Int?) -> PlannedStep {
        let how = size.map { "Copy the MetaService program (\($0 / 1_048_576) MB) to \(box)/bin, and check it arrived whole." } ?? "Copy the MetaService program to \(box)/bin, and check it arrived whole."
        return PlannedStep(id: "agent", label: "Copy the MetaService program", changes: [how],
                           operations: [.putFile(path: box + "/bin/" + InstallPlan.programName, mode: "700", source: .agentBinary),
                                        .runAsAdmin(command: "chown \(user):\(user) \(box)/bin/\(InstallPlan.programName)")])
    }

    private static func enroll(_ options: RemoteInstallOptions) -> PlannedStep {
        let stagedToken = "/tmp/metaservice-enroll-\(options.name).token"
        return PlannedStep(id: "enroll", label: "Enroll it with the parent",
                    changes: ["Introduce it to the parent at \(options.rootURL) with a one-time token that is used once and then deleted."],
                    operations: [.putFile(path: stagedToken, mode: "600", source: .enrollToken),
                                 .runAsAdmin(command: "install -o \(user) -g \(user) -m 600 \(stagedToken) \(box)/state/enroll.token && rm -f \(stagedToken)"),
                                 .runAsAdmin(command: "runuser -u \(user) -- " + PlanScripts.enrollCommand(options, box: box)),
                                 .runAsAdmin(command: "rm -f \(box)/state/enroll.token")])
    }

    private static func unit(_ options: RemoteInstallOptions) -> PlannedStep {
        PlannedStep(id: "unit", label: "Write the service file", changes: ["Create \(unitFile): one new service that runs as \(user), may write only inside \(box), and cannot gain privileges."],
                    operations: [.putFile(path: unitFile, mode: "644", source: .text(unitText(options)))])
    }

    private static func start() -> PlannedStep {
        PlannedStep(id: "start", label: "Start the service", changes: ["Start \(service) now and at every boot. It listens only on 127.0.0.1 of that computer."],
                    operations: [.runAsAdmin(command: "systemctl daemon-reload && systemctl enable --now \(service)")])
    }
}
