//
//  ThreadSanitizer.swift
//  ThreadSanitizerSimulator
//
//  Created by Benji Encz on 11/14/16.
//  Copyright © 2016 Benjamin Encz. All rights reserved.
//

import Foundation

class ObservedInstance<T> {

    fileprivate var objectUuid = UUID()
    fileprivate var vectorClock: Int = 0
    var racingThreads: [Thread] = []

    private var _value: T

    var value: T {
        get {
            objc_sync_enter(self)
            defer { objc_sync_exit(self) }

            if !self.threadLocalVectorMatchesActualVector() {
                self.racingThreads.append(Thread.current)
                self.vectorClock += 1
            } else {
                self.vectorClock += 1
                // Keep synced thread up to date
                Thread.current.threadDictionary[self.objectUuid] = self.vectorClock
            }

            return self._value
        }
        set {
            objc_sync_enter(self)
            defer { objc_sync_exit(self) }

            if !self.threadLocalVectorMatchesActualVector() {
                self.racingThreads.append(Thread.current)
                self.vectorClock += 1
            } else {
                self.vectorClock += 1
                // Keep synced thread up to date
                Thread.current.threadDictionary[self.objectUuid] = self.vectorClock
            }

            self._value = newValue
        }
    }

    init(value: T) {
        self._value = value
    }

    private func threadLocalVectorMatchesActualVector() -> Bool {
        guard let threadVector = Thread.current.threadDictionary[self.objectUuid] as? Int else {
            return false
        }

        if threadVector == self.vectorClock {
            return true
        } else {
            return false
        }
    }

}

func withLock<T>(access object: ObservedInstance<T>, closure: (ObservedInstance<T>) -> Void) {
    objc_sync_enter(object)
    Thread.current.threadDictionary[object.objectUuid] = object.vectorClock
    closure(object)
    objc_sync_exit(object)
}
