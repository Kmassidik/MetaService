import Hummingbird
import RootStore

/// Two listeners, so that what needs no sign-in never shares an address with what is open to the network.
///
/// Operator listener (this machine only): the panel and /api. The operator signs in with the admin login; reads also need the right Host, writes the exact Origin and the session's CSRF header.
/// Agent listener (reachable by Agents and chats): /health, enroll, heartbeat, bundle download and the AI proxy. Each route needs its own token or key.
func buildOperatorApplication(services: Services) -> some ApplicationProtocol {
    let router = baseRouter()
    let guards = Guards(services: services)
    AuthRoutes(services: services, guards: guards).register(on: router.group())
    OperatorRoutes(services: services, guards: guards).register(on: router.group())
    WorkloadRoutes(services: services, guards: guards).register(on: router.group())
    BundleRoutes(services: services, guards: guards).registerOperator(on: router.group())
    BrainRoutes(services: services, guards: guards).registerOperator(on: router.group())
    ScanRoutes(services: services, guards: guards).register(on: router.group())
    UIRoutes(directory: services.config.uiDirectory).register(on: router.group())
    return Application(router: router, configuration: .init(address: .hostname(services.config.bind, port: services.config.port)))
}

func buildAgentApplication(services: Services) -> some ApplicationProtocol {
    let router = baseRouter()
    let guards = Guards(services: services)
    AgentRoutes(services: services, guards: guards).register(on: router.group())
    BundleRoutes(services: services, guards: guards).registerAgent(on: router.group())
    BrainRoutes(services: services, guards: guards).registerAgent(on: router.group())
    return Application(router: router, configuration: .init(address: .hostname(services.config.agentListenBind, port: services.config.agentListenPort)))
}

private func baseRouter() -> Router<RootContext> {
    let router = Router(context: RootContext.self)
    // First added is outermost: the headers must wrap the error mapping, so refusals carry them too.
    router.add(middleware: SecurityHeadersMiddleware())
    router.add(middleware: ErrorMiddleware())
    router.get("/health") { _, _ in try Json.response(["status": "ok"]) }
    return router
}
