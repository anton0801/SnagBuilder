import Foundation

@MainActor
final class Depot {

    static let shared = Depot()

    private var bins: [String: Any] = [:]

    private init() {}

    func lodge<T>(_ instance: T, as type: T.Type) {
        bins[String(describing: type)] = instance
    }

    func draw<T>(_ type: T.Type) -> T {
        let key = String(describing: type)
        if let instance = bins[key] as? T {
            return instance
        }
        let built = raise(type)
        bins[key] = built
        return built
    }

    private func raise<T>(_ type: T.Type) -> T {
        switch String(describing: type) {
        case String(describing: Site.self):
            return Site.staffed() as! T
        case String(describing: Snagger.self):
            return Snagger(site: draw(Site.self)) as! T
        default:
            fatalError("Depot: no builder for \(type)")
        }
    }
}
