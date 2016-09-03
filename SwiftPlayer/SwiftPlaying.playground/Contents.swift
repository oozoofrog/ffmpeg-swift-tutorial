//: Playground - noun: a place where people can play

import UIKit
import AVFoundation
import XCPlayground

XCPlaygroundPage.currentPage.needsIndefiniteExecution = true

class Test: Operation {
    override var isConcurrent: Bool {
        return true
    }
    private var _executing: Bool = false
    override var isExecuting: Bool {
        get {
            return _executing
        }
        set {
            willChangeValue(forKey: "isExecuting")
            _executing = newValue
            didChangeValue(forKey: "isExecuting")
        }
    }
    deinit {
        print("finished")
    }
    override func main() {
        isExecuting = true
        for i in 0..<1000 {
            print(i)
            print(self.isExecuting)
        }
        self.isExecuting = false
    }
}

var t: Test? = Test()

func test()  {
    t?.start()
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        t?.cancel()
        print(t?.isExecuting)
        t = nil
    }
}

test()
