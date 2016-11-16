//
//  DataRaceDetectorTests
//  DataRaceDetectorTests.swift
//
//  Created by Benji Encz on 11/14/16.
//  Copyright © 2016 Benjamin Encz. All rights reserved.
//

import XCTest
@testable import DataRaceDetector

class DataRaceDetectorTests: XCTestCase {

    /// We spawn 20 threads that write to the observed value without synchronization
    /// and expect to detect 19 racing threads.
    ///
    /// As discussed in the implementation, we currently only record racing threads at the point of
    /// memory access. So even though the first thread participates in a race, we don't mark it 
    /// as racing, as we only identify the race after a second thread accesses the observed value.
    func testWithDataRace() {
        let instance = ObservedValue(value: 1)

        let dispatchGroup = DispatchGroup()

        (1...20).forEach { i in
            dispatchGroup.enter()

            Thread {
                instance.value = i
                dispatchGroup.leave()
            }.start()
        }

        dispatchGroup.wait()

        synchronized(instance) {
            print("Racing Threads (Unsynchronized):")
            print(instance.racingThreads)
            XCTAssertTrue(instance.racingThreads.count == 19)
        }
    }

    /// We spawn 20 threads that write to the observed value and use the `synchronized` function.
    /// We expect to detect no data races.
    func testSynchronized() {
        let instance = ObservedValue(value: 1)

        let dispatchGroup = DispatchGroup()

        (1...20).forEach { i in
            dispatchGroup.enter()

            Thread {
                synchronized(instance) {
                    instance.value = i
                    dispatchGroup.leave()
                }
            }.start()
        }

        dispatchGroup.wait()

        synchronized(instance) {
            XCTAssertTrue(instance.racingThreads.isEmpty)
        }
    }

    /// We access the value unsynchronized, multiple times, but only from a single thread.
    /// We expect to detect no data races.
    func testSingleThreadAccess() {
        let instance = ObservedValue(value: 1)

        instance.value = 5
        _ = instance.value
        instance.value = 12

        XCTAssertTrue(instance.racingThreads.isEmpty)
    }

    /// We spawn 20 threads that read the observed value unsynchronized. 
    /// We expect to detect no data races, as a data race requires concurrent access to a value
    /// where at least one access is writing.
    func testReadOnly() {
        let instance = ObservedValue(value: 1)

        let dispatchGroup = DispatchGroup()

        (1...20).forEach { i in
            dispatchGroup.enter()

            Thread {
                _ = instance.value
                dispatchGroup.leave()
            }.start()
        }

        dispatchGroup.wait()

        synchronized(instance) {
            XCTAssertTrue(instance.racingThreads.isEmpty)
        }
    }

    /// We spawn 20 threads that read the observed value unsynchronized and one thread that writes
    /// unsynchronized.
    /// We expect to detect no data races, as a data race requires concurrent access to a value
    /// where at least one access is writing.
    func testManyReadsOneWrite() {
        let instance = ObservedValue(value: 1)

        let dispatchGroup = DispatchGroup()

        (1...20).forEach { i in
            dispatchGroup.enter()

            Thread {
                _ = instance.value
                dispatchGroup.leave()
            }.start()
        }

        dispatchGroup.enter()
        Thread {
            instance.value = 4
            dispatchGroup.leave()
        }.start()

        dispatchGroup.wait()

        synchronized(instance) {
            XCTAssertTrue(instance.racingThreads.count > 0)
        }
    }

    /// We use dispatch groups to create three reading unsynchronized threads.
    /// We also spawn a writing unsynchronized thread that accesses the value after the
    /// three reading threads completed. We expect to detect the writing as the racing thread.
    /// While we are using a `DispatchGroup` to ensure that the write happens after the read,
    /// our data race detector does not understand this synchronization mechanism and therefore 
    /// will still detect a race.
    ///
    /// As discussed in the implementation, we currently only record racing threads at the point of
    /// memory access. So even though the three reading threads participates in a race, we don't mark them
    /// as racing, as we only identify the race after the writing thread accesses the observed value.
    func testWriteAfterReadUnsynced() {
        let instance = ObservedValue(value: 1)

        let dispatchGroup = DispatchGroup()

        (1...3).forEach { i in
            dispatchGroup.enter()

            Thread {
                _ = instance.value
                dispatchGroup.leave()
            }.start()
        }

        dispatchGroup.wait()

        let secondDispatchGroup = DispatchGroup()

        secondDispatchGroup.enter()
        Thread {
            instance.value = 7
            secondDispatchGroup.leave()
        }.start()

        secondDispatchGroup.wait()

        synchronized(instance) {
            XCTAssertTrue(instance.racingThreads.count == 1)
        }
    }

    /// Inverted test case of `testWriteAfterReadUnsynced`.
    func testReadAfterWriteUnsynced() {
        let instance = ObservedValue(value: 1)

        let secondDispatchGroup = DispatchGroup()
        secondDispatchGroup.enter()

        Thread {
            instance.value = 7
            secondDispatchGroup.leave()
        }.start()

        secondDispatchGroup.wait()

        let dispatchGroup = DispatchGroup()

        (1...3).forEach { i in
            dispatchGroup.enter()

            Thread {
                _ = instance.value
                dispatchGroup.leave()
            }.start()
        }

        dispatchGroup.wait()

        synchronized(instance) {
            XCTAssertTrue(instance.racingThreads.count == 3)
        }
    }

}
