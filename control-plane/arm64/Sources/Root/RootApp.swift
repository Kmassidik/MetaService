import Hummingbird
import HummingbirdWebSocket
import RootStore

/// Two listeners, so that what needs no sign-in never shares an address with what is open to the network.
///
/// Operator listener (this machine only): the panel and /api. The operator signs in with the admin login; reads also need the right Host, writes the exact Origin and the session's CSRF header.
/// Agent listener (reachable by Agents and chats): /health, enroll, heartbeat, bundle download and the AI proxy. Each route needs its own token or key.
func buildOperatorApplication(services: Services) -> some ApplicationProtocol {
    // The public ports answer on `<label>.<domain>`, with every method and every path, so this is handed to the router before
    // any route is added: a middleware only applies to the endpoints registered after it, `/health` included. It lets every
    // other Host through untouched.
    let router = baseRouter(publicSite: services.config.cookiesAreSecure, ports: SandboxPortRoutes(services: services))
    let guards = Guards(services: services)
    AuthRoutes(services: services, guards: guards).register(on: router.group())
    OperatorRoutes(services: services, guards: guards).register(on: router.group())
    MachineSettingsRoutes(services: services, guards: guards).register(on: router.group())
    WorkloadRoutes(services: services, guards: guards).register(on: router.group())
    BundleRoutes(services: services, guards: guards).registerOperator(on: router.group())
    BrainRoutes(services: services, guards: guards).registerOperator(on: router.group())
    ScanRoutes(services: services, guards: guards).register(on: router.group())
    RemoteRoutes(services: services, guards: guards).register(on: router.group())
    RemoteInstallRoutes(services: services, guards: guards).register(on: router.group())
    TerminalRoutes(services: services, guards: guards).register(on: router.group())
    SshKeyRoutes(services: services, guards: guards).register(on: router.group())
    AppRoutes(services: services, guards: guards).register(on: router.group())
    StatsRoutes(services: services, guards: guards).register(on: router.group())
    GpuCheckRoutes(services: services, guards: guards).register(on: router.group())
    ImagesRoutes(services: services, guards: guards).register(on: router.group())
    HelperUpdateRoutes(services: services, guards: guards).register(on: router.group())
    // The panel's sandbox pages: API keys, the live list, kill and pause, and the usage table. Operator guards, as every
    // panel route above.
    SandboxPanelRoutes(services: services, guards: guards).register(on: router.group())
    // The public sandbox API answers on this app (the panel's own name), with its own key guard: no cookie, no CSRF.
    // It is registered before the UI catch-all so a `/v2/...` request is never answered by the panel's HTML.
    SandboxApiRoutes(services: services, gate: SandboxApiGuard(services: services), helper: services.sandboxHelper).register(on: router.group())
    UIRoutes(directory: services.config.uiDirectory).register(on: router.group())
    return Application(router: router, server: .http1WebSocketUpgrade(webSocketRouter: consoleRouter(services: services, guards: guards), configuration: consoleSocketConfiguration),
                       configuration: .init(address: .hostname(services.config.bind, port: services.config.port)))
}

/// The console socket has its own router: only `/api/terminal/{ticket}` can ever upgrade.
private func consoleRouter(services: Services, guards: Guards) -> Router<TerminalContext> {
    let router = Router(context: TerminalContext.self)
    router.add(middleware: ErrorMiddleware())
    TerminalRoutes(services: services, guards: guards).registerSocket(on: router)
    return router
}

private let consoleSocketConfiguration = HTTP1WebSocketUpgradeChannel.Configuration(ws: .init(maxFrameSize: TerminalBridge.socketFrameBytes))

func buildAgentApplication(services: Services) -> some ApplicationProtocol {
    let router = baseRouter(publicSite: false)
    let guards = Guards(services: services)
    AgentRoutes(services: services, guards: guards).register(on: router.group())
    BundleRoutes(services: services, guards: guards).registerAgent(on: router.group())
    BrainRoutes(services: services, guards: guards).registerAgent(on: router.group())
    return Application(router: router, configuration: .init(address: .hostname(services.config.agentListenBind, port: services.config.agentListenPort)))
}

/// `publicSite`: the panel is served over https (through the Cloudflare connector on this machine). Then the browser is told to insist on https,
/// and the visitor's real address is read from the connector, so the lockout counts each visitor on their own.
/// `ports`: the operator app's public port route, inside the security headers and the error mapping, and outside every other route.
private func baseRouter(publicSite: Bool, ports: SandboxPortRoutes? = nil) -> Router<RootContext> {
    let router = Router(context: RootContext.self)
    // First added is outermost: the headers must wrap the error mapping, so refusals carry them too.
    router.add(middleware: SecurityHeadersMiddleware(hsts: publicSite))
    if publicSite { router.add(middleware: ClientAddressMiddleware()) }
    router.add(middleware: ErrorMiddleware())
    if let ports { router.add(middleware: ports) }
    router.get("/health") { _, _ in try Json.response(["status": "ok"]) }
    return router
}
