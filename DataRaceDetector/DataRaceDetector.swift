//
//  DataRaceDetector.swift
//  DataRaceDetector
//
//  Created by Benji Encz on 11/14/16.
//  Copyright © 2016 Benjamin Encz. All rights reserved.
//

import Foundation

/// A box around a value that allows for detection of potential data races. 
/// This implementation is based on the ideas of LLVM's Thread Sanitizer and is
/// only intended for educational purposes.
/// 
/// The paper describing Thread Sanitizer can be found here:
/// http://static.googleusercontent.com/media/research.google.com/en//pubs/archive/35604.pdf
///
/// Apple also dedicated a part of a 2016 WWDC session to discussing Thread Sanitizer:
/// https://developer.apple.com/videos/play/wwdc2016/412/?time=993
/// 
/// # How it works
///
/// All accesses to the boxed value are recorded. For each access this type stores
/// a `MemoryAccessRecord` that keeps track of which thread accessed the value and
/// whether the access was a read or a write operation.
/// Each thread associates a counter with each read and write operation to an
/// `ObservedValue`. For subequent reads and writes these counters are increased.
///
/// The `ObservedValue` itself maintains a data structure that stores these counters
/// for all threads that access the boxed value.
///
/// Whenever a synchronization on an `ObservedValue` occurs, via the `synchronized` function,
/// the current thread gets access to all `MemoryAccessRecord`s and their respective counters stored in
/// `ObservedValue`. This means that the current thread now has access to all the `MemoryAccessRecord`s
/// of all other threads. Later on the `ObservedValue` will use that fact to check for a correct 
/// synchronization.
///
/// When a value is accessed, the access is first recorded, as discussed above. After that
/// the data race detection occurs. 
/// 
/// To detect a data race, we iterate over all memory access records stored in the `ObservedValue`
/// and compare them with the memory access records in thread specific storage.
///
/// A data race is detected when one of the memory access records in
/// the `ObservedValue` does not match the memory access records stored in the current thread - and
/// one of the following conditions is true:
///
/// 1. The current thread is reading and the mismatched memory access record represents a write
/// 2. The current thread is writing and the mismatched memory access record represents a read
/// 3. The current thread is writing and the mismatched memory access record represents a write
///
/// If the memory record in question represents a read and the current thread is reading, we don't
/// have a data race, since a data race is defined as concurrent access by multiple threads of which
/// at least one is writing.
class ObservedValue<T> {

    /// Unique identifier for this observed value. Also serves as a key for storing memory access
    /// records in thread specifc storage. Each thread keeps a dictionary of all memory access events
    /// per memory UUID.
    public private(set) var memoryUUID = UUID()

    /// Mapping from `MemoryAccess` records to their specific vector clocks. These vector clocks
    /// are compared to thread specific vector clocks in order to detect data races.
    public private(set) var vectorClocks: VectorClocks = [:]

    /// A set of threads that we identified as potentially racing. 
    ///
    /// - Note: Due to the simplified algorithm, this data race detector will detect slightly fewer
    /// racing threads than the actual algorithm. I.e. we only mark threads as racing at the point 
    /// of memory access, but we never validate previous memory accesses to check if they are racing
    /// based on later accesses to the same memory location. In practice this means that we detect the same
    /// amount of potential data races, but we don't always capture all racing threads.
    public private(set) var racingThreads: Set<Thread> = []

    /// Storage for the value that is being observed.
    private var _value: T

    /// Public accessor that records all accesses to the underlying value and attempts to detect
    /// data races.
    public var value: T {
        get {
            // At this point we need to synchronize racing threads in order to avoid crashes due
            // to races on data structures in the `ObservedValue` itself.
            objc_sync_enter(self)
            defer { objc_sync_exit(self) }

            self.updateVectorClocks(accessType: .read)

            if self.isRace(accessType: .read) {
                self.racingThreads.insert(Thread.current)
            }

            return self._value
        }
        set {
            // At this point we need to synchronize racing threads in order to avoid crashes due
            // to races on data structures in the `ObservedValue` itself.
            objc_sync_enter(self)
            defer { objc_sync_exit(self) }

            self.updateVectorClocks(accessType: .write)

            if self.isRace(accessType: .write) {
                self.racingThreads.insert(Thread.current)
            }

            self._value = newValue
        }
    }

    init(value: T) {
        self._value = value
    }

    /// Increments the vector clock of this observed value and updates the vector clock of the current
    /// thread to that new value.
    /// If the current thread doesn't yet have a vector clock record for this observed value, this
    /// method initializes it.
    ///
    /// A data race is detected when one of the memory access records in
    /// the `ObservedValue` does not match the memory access records stored in the current thread - and
    /// one of the following conditions is true:
    ///
    /// 1. The current thread is reading and the mismatched memory access record represents a write
    /// 2. The current thread is writing and the mismatched memory access record represents a read
    /// 3. The current thread is writing and the mismatched memory access record represents a write
    ///
    /// If the memory record in question represents a read and the current thread is reading, we don't
    /// have a data race, since a data race is defined as concurrent access by multiple threads of which
    /// at least one is writing.
    private func updateVectorClocks(accessType: AccessType) {
        // Generate a key based on the current thread and the memory access type.
        // This Data Race detector only remembers the vector clock of the latest read and write event
        // for each thread/memory combination; subsequent accesses replace previous ones.
        let memoryAccessKey = MemoryAccessRecord(thread: Thread.current, accessType: accessType)

        // Increment the vector clock for this thread & memory access type by one, or 
        // initialize the value to 0 if none is present.
        self.vectorClocks[memoryAccessKey] = self.vectorClocks[memoryAccessKey] ?? 0 + 1

        let newVectorClockValue = self.vectorClocks[memoryAccessKey]

        // Update the current thread's vector clocks to match the `ObservedValue` vector clocks for the current
        // thread/memory access combination. 
        // This just ensures that the current thread keeps its own memory access records up to date.
        if var currentThreadClocks = (Thread.current.threadDictionary[self.memoryUUID] as? VectorClocks) {
            // If the thread has an existing record of vector clocks for this memory UUID, update it.
            currentThreadClocks[memoryAccessKey] = newVectorClockValue
            Thread.current.threadDictionary[self.memoryUUID] = currentThreadClocks
        } else {
            // If the thread has no records for this memory UUID, initialize the record.
            Thread.current.threadDictionary[self.memoryUUID] = [memoryAccessKey : newVectorClockValue]
        }
    }

    /// Compares all memory access records of this `ObservedValue` to the ones of the Thread that is
    /// currently accessing the value.
    private func isRace(accessType: AccessType) -> Bool {
        // Get the thread specific vector clocks for  this memory UUID.
        guard let threadVectorClocks = Thread.current.threadDictionary[self.memoryUUID] as? VectorClocks else {
            precondition(false, "Precondition violated: vector clocks need to be updated before checking for data race." +
            "After that update, the thread local storage should contain an entry for the current memoryUUID.")
        }

        // Iterate over all thread specific vector clock values, for all reads and writes on this object
        // and compare them to the vector values that are stored in thread local storage.
        for (threadKey, clock) in self.vectorClocks {
            // There's no data race, if we're just  reading and are not in sync with other readers,
            // therefore we can skip comparing vector clocks in this case.
            if accessType == .read && threadKey.accessType == .read {
                continue
            }

            // If the current thread is writing, or if the vector clock we're looking for belongs
            // to a write access AND we cannot find the vector clock value in the thread's local storage,
            // we have detected a data race, since we have a combination of reads and writes and
            // the current access to the value is not synchronized.
            guard let threadVectorClock = threadVectorClocks[threadKey] else {
                return true
            }

            // If we can find the vector clock value, but the values don't match up, we also have 
            // detected a data race. The current thread has synchronized with the other thread at some
            // earlier point, but further reads/writes ocurred which would have required another
            // synchronization. (TODO: write test case that triggers this code path).
            if threadVectorClock != clock {
                return true
            }
        }

        // If we matched none of the conditions above, we haven't detected a data race.
        return false
    }

}

/// A mapping from a memory access record to a vector clock.
typealias VectorClocks = [MemoryAccessRecord: Int]

/// Differentiates between reading and writing memory access events.
enum AccessType {
    case read
    case write
}

/// Identifies the combination of a thread and the memory access type of a memory access event.
/// This type is used as a key for storing vector clocks. We store one vector clock per 
/// `MemoryAccessRecord` instance.
class MemoryAccessRecord: NSObject {
    let thread: Thread
    let accessType: AccessType

    init(thread: Thread, accessType: AccessType) {
        self.thread = thread
        self.accessType = accessType
    }
}

extension MemoryAccessRecord {
    override var hashValue: Int {
        return self.thread.hashValue ^ self.accessType.hashValue
    }

    static func ==(lhs: MemoryAccessRecord, rhs: MemoryAccessRecord) -> Bool {
        return lhs.thread == rhs.thread && lhs.accessType == rhs.accessType
    }
}
