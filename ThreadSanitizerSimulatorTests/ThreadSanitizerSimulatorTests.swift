//
//  ThreadSanitizerSimulatorTests.swift
//  ThreadSanitizerSimulatorTests
//
//  Created by Benji Encz on 11/14/16.
//  Copyright © 2016 Benjamin Encz. All rights reserved.
//

import XCTest
@testable import ThreadSanitizerSimulator

class ThreadSanitizerSimulatorTests: XCTestCase {

    func testWithRaceCondition() {
        let instance = ObservedInstance(value: ExampleType())

        let dispatchQueue = DispatchQueue(label: "TestQueue", attributes: .concurrent)
        let dispatchGroup = DispatchGroup()

        (1...20).forEach { i in
            dispatchGroup.enter()

            dispatchQueue.async {
                instance.value.number = i
                instance.value.string = "Racy! \(i)"
                dispatchGroup.leave()
            }
        }

        dispatchGroup.wait()

        withLock(access: instance) { instance in
            print("Racing Threads (Unsynchronized):")
            print(instance.racingThreads)
            XCTAssertTrue(instance.racingThreads.count > 0)
        }
    }

    func testSynchronized() {
        let instance = ObservedInstance(value: ExampleType())

        let dispatchQueue = DispatchQueue(label: "TestQueue", attributes: .concurrent)
        let dispatchGroup = DispatchGroup()

        (1...20).forEach { i in
            dispatchGroup.enter()

            dispatchQueue.async {
                withLock(access: instance) { instance in
                    instance.value.number = i
                    instance.value.string = "Racy! \(i)"
                    dispatchGroup.leave()
                }
            }
        }

        dispatchGroup.wait()

        withLock(access: instance) { instance in
            print("Racing Threads (Synchronized):")
            print(instance.racingThreads)
            XCTAssertTrue(instance.racingThreads.isEmpty)
        }
    }

}
