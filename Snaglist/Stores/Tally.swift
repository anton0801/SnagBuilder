import Foundation
import Combine

@MainActor
final class Tally: ObservableObject {
    
    @Published var navigateToWeb = false {
        didSet {
            if navigateToWeb {
                deadlineTask?.cancel()
                uiLocked = true
            }
        }
    }

    @Published var showPermissionPrompt = false
    @Published var showOfflineView = false

    private let snagger: Snagger
    
    @Published var navigateToMain = false {
        didSet {
            if navigateToMain {
                deadlineTask?.cancel()
                uiLocked = true
            }
        }
    }

    private var deadlineTask: Task<Void, Never>?

    init() {
        self.snagger = Depot.shared.draw(Snagger.self)
        wireStamps()
    }
    
    private var cancellables = Set<AnyCancellable>()

    private func wireStamps() {
        snagger.stampStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stamp in
                self?.settle(stamp)
            }
            .store(in: &cancellables)
    }

    func ignite() {
        snagger.ensureOpened()
        armDeadline()
    }

    func ingestMarks(_ data: [String: Any]) {
        Task {
            snagger.takeMarks(data)
            await snagger.walk()
        }
    }
    
    private var uiLocked = false

    func skipConsent() {
        showPermissionPrompt = false
        snagger.skipNotify()
    }

    func networkConnectivityChanged(_ connected: Bool) {
        if !connected {
            showOfflineView = true
        }
    }

    private func settle(_ stamp: Stamp) {
        guard !uiLocked else { return }

        switch stamp {
        case .pending:
            break
        case .notify:
            showPermissionPrompt = true
        case .handover:
            navigateToWeb = true
        case .reject:
            navigateToMain = true
        }
    }
    
    func ingestNotes(_ data: [String: Any]) {
        snagger.takeNotes(data)
    }

    func acceptConsent() {
        snagger.acceptNotify {
            self.showPermissionPrompt = false
        }
    }
    

    private func armDeadline() {
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self = self else { return }
            if self.snagger.reportLapse() {
                self.settle(.reject)
            }
        }
    }
    
    deinit {
        deadlineTask?.cancel()
    }
    
}
