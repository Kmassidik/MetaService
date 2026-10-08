import Hummingbird
import RootStore

/// The route table. Public: /health and the Agent enroll door. Everything else checks a session or a machine token.
func buildApplication(services: Services) -> some ApplicationProtocol {
    let router = Router(context: RootContext.self)
    // First added is outermost: the headers must wrap the error mapping, so refusals carry them too.
    router.add(middleware: SecurityHeadersMiddleware())
    router.add(middleware: ErrorMiddleware())
    let guards = Guards(services: services)
    router.get("/health") { _, _ in try Json.response(["status": "ok"]) }
    AgentRoutes(services: services, guards: guards).register(on: router.group())
    OperatorRoutes(services: services, guards: guards).register(on: router.group())
    AuthRoutes(services: services, guards: guards).register(on: router.group())
    return Application(router: router, configuration: .init(address: .hostname(services.config.bind, port: services.config.port)))
}
