import OneState
import CasePaths

public extension StoreViewProvider where State: Equatable, Access == Write {
    func `case`<Case>(_ casePath: CasePath<State, Case>) -> Case? where Case: Equatable {
        storeView.value(for: \.[case: CaseIndex(casePath: casePath)])
    }

    func `case`<Case>(_ casePath: CasePath<State, Case>) -> StoreView<Root, Case?, Write> {
        storeView[case: CaseIndex(casePath: casePath)]
    }
}

#if canImport(SwiftUI)
import SwiftUI

public extension StoreViewProvider where State: Equatable, Access == Write {
    func `case`<Value, Case>(_ casePath: CasePath<Value, Case>, clearValue: Value) -> Binding<Case?> where State == Writable<Value>, Value: Equatable, Case: Equatable {
        Binding<Case?> {
            storeView.value(for: \.[case: CaseIndex(casePath: casePath)].wrappedValue)
        } set: { newValue in
            setValue(newValue.map { casePath.embed($0) } ?? clearValue, at: \.self)
        }
    }

    func `case`<Value, Case>(_ casePath: CasePath<Value, Case>, clearValue: Value) -> Binding<StoreView<Root, Case?, Write>> where State == Writable<Value>, Value: Equatable, Case: Equatable {
        self[dynamicMember: \State[case: CaseIndex(casePath: casePath, clearValue: clearValue)]]
    }
}

#endif

final class CaseIndex<Enum, Case>: Hashable, @unchecked Sendable {
    let casePath: CasePath<Enum, Case>
    var clearValue: Enum?

    init(casePath: CasePath<Enum, Case>, clearValue: Enum? = nil) {
        self.casePath = casePath
        self.clearValue = clearValue
    }
    
    static func == (lhs: CaseIndex, rhs: CaseIndex) -> Bool {
        return true
    }
    
    func hash(into hasher: inout Hasher) { }
}

extension Writable {
    subscript<Case> (case casePath: CaseIndex<Value, Case>) -> Writable<Case?> {
        get {
            Writable<Case?>(wrappedValue: casePath.casePath.extract(from: self.wrappedValue))
        }
        set {
            guard let newValue = newValue.wrappedValue.map({
                Writable(wrappedValue: casePath.casePath.embed($0))
            }) ?? casePath.clearValue.map(Writable.init(wrappedValue:)) else { return }
            self = newValue
        }
    }
}

extension Optional {
    subscript<Case> (case casePath: CaseIndex<Wrapped, Case>) -> Case? {
        get {
            flatMap { casePath.casePath.extract(from: $0) }
        }
        set {
            guard let newValue = newValue.map({
                casePath.casePath.embed($0)
            }) ?? casePath.clearValue else { return }
            self = newValue
        }
    }
}

extension Equatable {
    subscript<Case> (case casePath: CaseIndex<Self, Case>) -> Case? {
        get {
            casePath.casePath.extract(from: self)
        }
        set {
            guard let value = newValue else { return }
            self = casePath.casePath.embed(value)
        }
    }
}
