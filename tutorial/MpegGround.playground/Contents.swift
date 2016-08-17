//: Playground - noun: a place where people can play

import UIKit

protocol PointerCastable {}

protocol UnsafePointerable {
    init(_ other: UnsafePointer<Pointee>)
    init?(_ other: UnsafePointer<Pointee>?)
    init(_ other: UnsafeMutablePointer<Pointee>)
    init?(_ other: UnsafeMutablePointer<Pointee>?)
    associatedtype Pointee
    var pointee: Pointee { get }
    func withMemoryRebound<T, Result>(to: T.Type, capacity count: Int, _ body: (UnsafeMutablePointer<T>) throws -> Result) rethrows -> Result
}

extension UnsafePointer: PointerCastable, UnsafePointerable {}
extension UnsafeMutablePointer: PointerCastable, UnsafePointerable {}

protocol UnsafeRawPointerable{
    init<T>(_ other: UnsafePointer<T>)
    init?<T>(_ other: UnsafePointer<T>?)
    init<T>(_ other: UnsafeMutablePointer<T>)
    init?<T>(_ other: UnsafeMutablePointer<T>?)
}

extension UnsafeRawPointer: UnsafeRawPointerable, PointerCastable {}
extension UnsafeMutableRawPointer: UnsafeRawPointerable, PointerCastable {}

extension PointerCastable where Self: UnsafePointerable {
    func cast<P: UnsafePointerable, M>() -> P? where P.Pointee == M {
        if self is P {
            return self as? P
        }
        let ptr = self.withMemoryRebound(to: M.self, capacity: MemoryLayout<M>.stride){$0}
        return P(ptr)
    }
    func cast<P: UnsafePointerable, M>() -> P where P.Pointee == M {
        if self is P {
            return self as! P
        }
        let ptr = self.withMemoryRebound(to: M.self, capacity: MemoryLayout<M>.stride){$0}
        return P(ptr)
    }
    func castRaw<R: UnsafeRawPointerable, T>(from: T.Type) -> R? {
        if R.self == UnsafeRawPointer.self {
            let ptr: UnsafePointer<T> = self.cast()
            return R(ptr)
        }
        let ptr: UnsafeMutablePointer<T> = self.cast()
        return R(ptr)
    }
    func castRaw<R: UnsafeRawPointerable, T>(from: T.Type) -> R {
        if R.self == UnsafeRawPointer.self {
            let ptr: UnsafePointer<T> = self.cast()
            return R(ptr)
        }
        let ptr: UnsafeMutablePointer<T> = self.cast()
        return R(ptr)
    }
}

extension PointerCastable where Self: UnsafeRawPointerable {
    func cast<P: UnsafePointerable, M>(to: M.Type) -> P where P.Pointee == M {
        if self is UnsafeRawPointer {
            let raw = self as! UnsafeRawPointer
            let ptr = raw.assumingMemoryBound(to: M.self)
            return P(ptr)
        } else {
            let raw: UnsafeMutableRawPointer = self as! UnsafeMutableRawPointer
            let ptr = raw.assumingMemoryBound(to: M.self)
            return P(ptr)
        }
    }
}


var a = "abcdefgaaaae"
let b = withUnsafePointer(to: &a){$0}
let c: UnsafeRawPointer = b.castRaw(from: String.self)
let d: UnsafePointer<String> = c.cast(to: String.self)
d.pointee