//
//  DictionaryRuntime.swift
//  XKey
//
//  Process-local lifecycle for the spell-check dictionary.
//

import Foundation

protocol DictionaryLoading: AnyObject {
    func isDictionaryAvailable(style: VNDictionaryManager.DictionaryStyle) -> Bool
    func isDictionaryLoaded(style: VNDictionaryManager.DictionaryStyle) -> Bool
    func loadDictionary(style: VNDictionaryManager.DictionaryStyle) throws
}

enum DictionaryRuntimeState: Equatable {
    case disabled
    case unavailable(VNDictionaryManager.DictionaryStyle)
    case loaded(VNDictionaryManager.DictionaryStyle)
    case failed(VNDictionaryManager.DictionaryStyle)
}

struct DictionaryRuntimeRefreshResult: Equatable {
    let previousState: DictionaryRuntimeState
    let newState: DictionaryRuntimeState
    let didChange: Bool
    let diagnostic: String?
}

final class DictionaryRuntime {
    static let shared = DictionaryRuntime(loader: VNDictionaryManager.shared)

    private struct LoadOutcome {
        let state: DictionaryRuntimeState
        let diagnostic: String?
    }

    private final class InFlightLoad {
        var outcome: LoadOutcome?
    }

    private let loader: DictionaryLoading
    private let onWaitForInFlight: (() -> Void)?
    private let condition = NSCondition()
    private var currentState: DictionaryRuntimeState = .disabled
    private var requestGeneration: UInt = 0
    private var inFlightLoads: [VNDictionaryManager.DictionaryStyle: InFlightLoad] = [:]

    var state: DictionaryRuntimeState {
        condition.lock()
        defer { condition.unlock() }
        return currentState
    }

    init(loader: DictionaryLoading,
         onWaitForInFlight: (() -> Void)? = nil) {
        self.loader = loader
        self.onWaitForInFlight = onWaitForInFlight
    }

    @discardableResult
    func refresh(enabled: Bool,
                 style: VNDictionaryManager.DictionaryStyle) -> DictionaryRuntimeRefreshResult {
        condition.lock()
        requestGeneration &+= 1
        let generation = requestGeneration

        guard enabled else {
            let result = publish(state: .disabled, diagnostic: nil)
            condition.unlock()
            return result
        }

        if let inFlightLoad = inFlightLoads[style] {
            condition.unlock()
            onWaitForInFlight?()
            condition.lock()
            while inFlightLoad.outcome == nil {
                condition.wait()
            }

            let result: DictionaryRuntimeRefreshResult
            if generation == requestGeneration, let outcome = inFlightLoad.outcome {
                result = publish(state: outcome.state, diagnostic: outcome.diagnostic)
            } else {
                result = unchangedResult()
            }
            condition.unlock()
            return result
        }

        let inFlightLoad = InFlightLoad()
        inFlightLoads[style] = inFlightLoad
        condition.unlock()

        let outcome = loadOutcome(style: style)

        condition.lock()
        inFlightLoad.outcome = outcome
        if inFlightLoads[style] === inFlightLoad {
            inFlightLoads[style] = nil
        }
        condition.broadcast()

        let result: DictionaryRuntimeRefreshResult
        if generation == requestGeneration {
            result = publish(state: outcome.state, diagnostic: outcome.diagnostic)
        } else {
            result = unchangedResult()
        }
        condition.unlock()
        return result
    }

    private func loadOutcome(style: VNDictionaryManager.DictionaryStyle) -> LoadOutcome {
        guard loader.isDictionaryAvailable(style: style) else {
            return LoadOutcome(state: .unavailable(style), diagnostic: nil)
        }

        if loader.isDictionaryLoaded(style: style) {
            return LoadOutcome(state: .loaded(style), diagnostic: nil)
        }

        do {
            try loader.loadDictionary(style: style)
            return LoadOutcome(state: .loaded(style), diagnostic: nil)
        } catch {
            return LoadOutcome(state: .failed(style), diagnostic: error.localizedDescription)
        }
    }

    private func publish(state: DictionaryRuntimeState,
                         diagnostic: String?) -> DictionaryRuntimeRefreshResult {
        let previousState = currentState
        currentState = state
        return DictionaryRuntimeRefreshResult(
            previousState: previousState,
            newState: state,
            didChange: previousState != state,
            diagnostic: diagnostic
        )
    }

    private func unchangedResult() -> DictionaryRuntimeRefreshResult {
        DictionaryRuntimeRefreshResult(
            previousState: currentState,
            newState: currentState,
            didChange: false,
            diagnostic: nil
        )
    }
}
