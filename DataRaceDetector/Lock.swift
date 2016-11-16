//
//  Lock.swift
//  DataRaceDetector
//
//  Created by Benji Encz on 11/16/16.
//  Copyright © 2016 Benjamin Encz. All rights reserved.
//

import Foundation

/// The only locking mechanism understood by this implementation of the Data Race detector.
/// Whenever a `ObservedValue`'s value is accessed from multiple threads, without using this 
/// locking mechanism, a data race will be detected, even though the instrumented code might be using
/// another synchronization mechanism that is not understood by this Data Race detector.
///
/// - Note: The value used as lock, needs to be the value that will be read/written inside of the closure
func synchronized<T>(_ value: ObservedValue<T>, closure: () -> Void) {
    // Besides our simulated lock, we also use an actual lock before accessing the observed value.
    // This avoids actual race conditions that could crash the instrumented application.
    objc_sync_enter(value)

    // When this lock is used with an observed value, the current thread's view of the other thread's 
    // vector clocks for the observed value are updated.
    // This allows the observed value to verify that the acessing thread has seen all reads/writes
    // that have happened previously.
    Thread.current.threadDictionary[value.memoryUUID] = value.vectorClocks
    closure()

    objc_sync_exit(value)
}
