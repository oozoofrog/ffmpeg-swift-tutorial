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

extension PointerCastable where Self: UnsafePointerable {
    func cast<P: UnsafePointerable, M>() -> P where P.Pointee == M {
        if self is P {
            return self as! P
        }
        let ptr = self.withMemoryRebound(to: M.self, capacity: MemoryLayout<M>.stride){$0}
        return P(ptr)
    }
}

var a = [UInt8](repeating: 1, count: 2)
var b = [UInt8](repeating: 2, count: 3)

var ap:UnsafePointer<UInt8> = a.withUnsafeBufferPointer { $0.baseAddress!}
var bp = b.withUnsafeBufferPointer(){$0.baseAddress!}

var c: (UnsafePointer<UInt8>, UnsafePointer<UInt8>) = (ap, bp)

var d = withUnsafePointer(to: &c) {$0}.withMemoryRebound(to: UnsafePointer<UInt8>.self, capacity: MemoryLayout<UnsafePointer<UInt8>>.stride){$0}

let e: UnsafePointer<UnsafePointer<UInt8>>? = d.cast()
let e1: UnsafeMutablePointer<UnsafePointer<UInt8>>? = d.cast()

