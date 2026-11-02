import Foundation
import Hummingbird
import RootCore
import RootStore

/// The bell: a signed-in user reads and marks their own notifications. The user is always the session's, never a value from the request.
struct NotificationRoutes {
    let services: Services
    let guards: Guards

    static let readsPerMinute = 120
    static let writesPerMinute = 60

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/notifications", use: list)
        group.post("/api/notifications/read", use: markRead)
    }

    private func list(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorRead(request)
        try guards.limit("notifications-read", per: context, max: Self.readsPerMinute, seconds: 60)
        let query = try refusing { try NotificationQuery.read(request.uri.queryParameters.map { (String($0.key), String($0.value)) }) }
        let page = try services.notifications.page(user: caller.name, page: query.page, pageSize: query.pageSize, unreadOnly: query.unreadOnly)
        return try Json.response(Page(notifications: page.rows, total: page.total, unreadCount: page.unreadCount, page: query.page, pageSize: query.pageSize))
    }

    private func markRead(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("notifications-write", per: context, max: Self.writesPerMinute, seconds: 60)
        let body = try await guards.body(request)
        let mark = try refusing { try NotificationMark.parse(body) }
        let now = services.clock.now
        let changed: Int
        switch mark {
        case .all: changed = try services.notifications.markAllRead(user: caller.name, now: now)
        case .ids(let ids): changed = try services.notifications.markRead(user: caller.name, ids: ids, now: now)
        }
        return try Json.response(Marked(marked: changed, unreadCount: try services.notifications.unreadCount(user: caller.name)))
    }

    private func refusing<T>(_ read: () throws -> T) throws -> T {
        do {
            return try read()
        } catch let refused as NotificationQuery.Refused {
            throw ApiFailure.invalid(refused.message)
        }
    }
}

private struct Page: Encodable {
    let notifications: [NotificationRow]
    let total: Int
    let unreadCount: Int
    let page: Int
    let pageSize: Int
}

private struct Marked: Encodable {
    let marked: Int
    let unreadCount: Int
}
