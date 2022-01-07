//
//  EventStreamTests.swift
//  EventStreamTests
//
//  Created by Daniel Coleman on 11/18/21.
//

import XCTest

import Observer
@testable import EventStreams

class EventStreamTests: XCTestCase {
    
    func testFilter() throws {
        
        let source: AnyTypedChannel<String> = SimpleChannel().asTypedChannel()
        
        let testEvents = (0..<10).map { index in "\(index)" }
        
        let filter: (String) -> Bool = { value in Int(value)!.isMultiple(of: 2) }
        
        let expectedEvents = testEvents.filter(filter)
        
        let sourceStream = EventStream<String>(source: source)
        let filteredStream = sourceStream.filter(filter)
        
        var receivedEvents = [String]()
        
        let subscription = filteredStream.subscribe { event in receivedEvents.append(event) }
        
        for event in testEvents {
            source.publish(event)
        }
        
        XCTAssertEqual(receivedEvents, expectedEvents)
    }

    func testMap() throws {
        
        let source: AnyTypedChannel<Int> = SimpleChannel().asTypedChannel()
        
        let testEvents = Array(0..<10)
        
        let transform: (Int) -> String = { value in "\(value)" }
        
        let expectedEvents = testEvents.map(transform)
        
        let sourceStream = EventStream<Int>(source: source)
        let mappedStream = sourceStream.map(transform)
        
        var receivedEvents = [String]()
        
        let subscription = mappedStream.subscribe { event in receivedEvents.append(event) }
        
        for event in testEvents {
            source.publish(event)
        }
        
        XCTAssertEqual(receivedEvents, expectedEvents)
    }
    
    func testFlatMap() throws {
        
        let source: AnyTypedChannel<Int> = SimpleChannel().asTypedChannel()
        
        let testEvents = Array(0..<10)
        
        let innerSources: [AnyTypedChannel<String>] = testEvents.map { _ in
         
            SimpleChannel().asTypedChannel()
        }
        
        let innerStreams = innerSources.map { innerSource in
         
            EventStream<String>(source: innerSource)
        }
        
        let transform: (Int) -> EventStream<String> = { index in
         
            innerStreams[index]
        }
                
        var expectedEvents = [String]()
        
        let sourceStream = EventStream<Int>(source: source)
        let flatMappedStream = sourceStream.flatMap(transform)
        
        var receivedEvents = [String]()
        
        let subscription = flatMappedStream.subscribe { event in receivedEvents.append(event) }
        
        for event in testEvents {
            
            let innerEvents = (0..<10).map { index in
            
                "\(event)-\(index)"
            }
            
            let innerSource = innerSources[event]
            
            innerSource.publish("Shouldn't be there")
            
            source.publish(event)
            
            for innerEvent in innerEvents {
                innerSource.publish(innerEvent)
                expectedEvents.append(innerEvent)
            }
        }
        
        for (index, innerSource) in innerSources.enumerated() {
            
            for innerIndex in 0..<10 {
                
                let additionalEvent = "Additional event \(innerIndex) from source \(index)"
                innerSource.publish(additionalEvent)
                expectedEvents.append((additionalEvent))
            }
        }
        
        XCTAssertEqual(receivedEvents, expectedEvents)
    }
    
    func testSwitchMap() throws {
        
        let source: AnyTypedChannel<Int> = SimpleChannel().asTypedChannel()
        
        let testEvents = Array(0..<10)
        
        let innerSources: [AnyTypedChannel<String>] = testEvents.map { _ in
         
            SimpleChannel().asTypedChannel()
        }
        
        let innerStreams = innerSources.map { innerSource in
         
            EventStream<String>(source: innerSource)
        }
        
        let transform: (Int) -> EventStream<String> = { index in
         
            innerStreams[index]
        }
                
        var expectedEvents = [String]()
        
        let sourceStream = EventStream<Int>(source: source)
        let switchMappedStream = sourceStream.switchMap(transform)
        
        var receivedEvents = [String]()
        
        let subscription = switchMappedStream.subscribe { event in receivedEvents.append(event) }
        
        for event in testEvents {
            
            let innerEvents = (0..<10).map { index in
            
                "\(event)-\(index)"
            }
            
            let innerSource = innerSources[event]
            
            innerSource.publish("Shouldn't be there")
            
            source.publish(event)
            
            for innerEvent in innerEvents {
                innerSource.publish(innerEvent)
                expectedEvents.append(innerEvent)
            }
        }
        
        var obsoleteSources = innerSources
        obsoleteSources.removeLast()
        
        for (index, innerSource) in obsoleteSources.enumerated() {
            
            for innerIndex in 0..<10 {
                
                let additionalEvent = "Additional event \(innerIndex) from source \(index)"
                innerSource.publish(additionalEvent)
            }
        }
        
        XCTAssertEqual(receivedEvents, expectedEvents)
    }
    
    func testMerge() throws {
        
        let sources: [AnyTypedChannel<Int>] = (0..<5).map { _ in
            
            SimpleChannel().asTypedChannel()
        }
        
        let sourceStreams = sources.map { source in
            
            EventStream<Int>(source: source)
        }
        
        let testEvents = sources.indices.map { index in
            
            Array(0..<10).map { innerIndex in index * 20 + innerIndex }
        }

        var expectedEvents = [Int]()
        
        let mergedStream = sourceStreams.merge()
        
        var receivedEvents = [Int]()
        
        let subscription = mergedStream.subscribe { event in receivedEvents.append(event) }
        
        for index in 0..<testEvents.flatMap { events in events }.count {
            
            let outerIndex = index % testEvents.count
            let innerIndex = index / testEvents.count
            
            let source = sources[outerIndex]
            let event = testEvents[outerIndex][innerIndex]
            
            source.publish(event)
            expectedEvents.append(event)
        }
        
        XCTAssertEqual(receivedEvents, expectedEvents)
    }
    
    func testCombineLatest() throws {
        
        typealias Combined = (String, String, String, String, String)
        
        let sources: [AnyTypedChannel<String>] = (0..<5).map { _ in
            
            SimpleChannel().asTypedChannel()
        }
        
        let sourceStreams = sources.map { source in
            
            EventStream<String>(source: source)
        }

        var expectedEvents = [Combined]()
        
        let combinedStream = sourceStreams[0]
            .combineLatest(sourceStreams[1], sourceStreams[2], sourceStreams[3], sourceStreams[4])
        
        var receivedEvents = [Combined]()
        
        let subscription = combinedStream.subscribe { event in receivedEvents.append(event) }
        
        for (index, source) in sources.enumerated() {
            
            source.publish("Initial \(index)");
        }
        
        expectedEvents.append(("Initial 0", "Initial 1", "Initial 2", "Initial 3", "Initial 4"))
        
        sources[0].publish("Next 0")
        expectedEvents.append(("Next 0", "Initial 1", "Initial 2", "Initial 3", "Initial 4"))

        sources[1].publish("Next 1")
        expectedEvents.append(("Next 0", "Next 1", "Initial 2", "Initial 3", "Initial 4"))
        
        sources[2].publish("Next 2")
        expectedEvents.append(("Next 0", "Next 1", "Next 2", "Initial 3", "Initial 4"))
    
        sources[3].publish("Next 3")
        expectedEvents.append(("Next 0", "Next 1", "Next 2", "Next 3", "Initial 4"))
        
        sources[4].publish("Next 4")
        expectedEvents.append(("Next 0", "Next 1", "Next 2", "Next 3", "Next 4"))

        XCTAssertTrue(receivedEvents.elementsEqual(expectedEvents, by: { first, second in
            
            first.0 == second.0 &&
            first.1 == second.1 &&
            first.2 == second.2 &&
            first.3 == second.3 &&
            first.4 == second.4
        }))
    }
    
    func testZip() throws {
        
        typealias Combined = (String, String, String, String, String)
        
        let sources: [AnyTypedChannel<String>] = (0..<5).map { _ in
            
            SimpleChannel().asTypedChannel()
        }
        
        let sourceStreams = sources.map { source in
            
            EventStream<String>(source: source)
        }

        var expectedEvents = [Combined]()
        
        let zippedStream = sourceStreams[0]
            .zip(sourceStreams[1], sourceStreams[2], sourceStreams[3], sourceStreams[4])
        
        var receivedEvents = [Combined]()
        
        let subscription = zippedStream.subscribe { event in receivedEvents.append(event) }
        
        for (index, source) in sources.enumerated() {
            
            source.publish("Initial \(index)");
        }
        
        expectedEvents.append(("Initial 0", "Initial 1", "Initial 2", "Initial 3", "Initial 4"))
        
        for (index, source) in sources.enumerated() {
            
            source.publish("Next \(index)");
        }
        
        expectedEvents.append(("Next 0", "Next 1", "Next 2", "Next 3", "Next 4"))

        XCTAssertTrue(receivedEvents.elementsEqual(expectedEvents, by: { first, second in
            
            first.0 == second.0 &&
            first.1 == second.1 &&
            first.2 == second.2 &&
            first.3 == second.3 &&
            first.4 == second.4
        }))
    }
    
    func testBufferOverlap() throws {
        
        let source: AnyTypedChannel<Int> = SimpleChannel().asTypedChannel()
        let sourceStream = EventStream<Int>(source: source)
        
        let size = 10
        let stride = 7
        
        let total = size + stride*(size - 1) - 1
        let testEvents = Array(0..<total)
        
        let expectedEvents = (0..<size-1).map { index in
            
            (0..<size).map { innerIndex in
                
                index * stride + innerIndex
            }
        }

        let bufferedStream = sourceStream.buffer(count: size, stride: stride)
        
        var receivedEvents = [[Int]]()
        
        let subscription = bufferedStream.subscribe { event in receivedEvents.append(event) }
        
        for event in testEvents {
            source.publish(event)
        }
        
        XCTAssertEqual(receivedEvents, expectedEvents)
    }
    
    func testBufferGaps() throws {
        
        let source: AnyTypedChannel<Int> = SimpleChannel().asTypedChannel()
        let sourceStream = EventStream<Int>(source: source)
        
        let size = 7
        let stride = 10
        
        let total = stride * stride
        let testEvents = Array(0..<total)
        
        let expectedEvents = (0..<stride).map { index in
            
            (0..<size).map { innerIndex in
                
                index * stride + innerIndex
            }
        }

        let bufferedStream = sourceStream.buffer(count: size, stride: stride)
        
        var receivedEvents = [[Int]]()
        
        let subscription = bufferedStream.subscribe { event in receivedEvents.append(event) }
        
        for event in testEvents {
            source.publish(event)
        }
        
        XCTAssertEqual(receivedEvents, expectedEvents)
    }
    
    func testAccumulate() throws {
        
        let source: AnyTypedChannel<Int> = SimpleChannel().asTypedChannel()
        let sourceStream = EventStream<Int>(source: source)
        
        let testEvents = Array(0..<15)
        let expectedEvents = testEvents.reduce(into: []) { partialResult, next in
            
            partialResult.append((partialResult.last ?? 0) + next)
        }

        let accumulatedStream = sourceStream.accumulate(initialValue: 0, publishInitial: true, +)
        
        var receivedEvents = [Int]()
        
        let subscription = accumulatedStream.subscribe { event in receivedEvents.append(event) }
        
        for event in testEvents {
            source.publish(event)
        }
        
        XCTAssertEqual(receivedEvents, expectedEvents)
    }
    
    func testDifferentiate() throws {
        
        let source: AnyTypedChannel<Int> = SimpleChannel().asTypedChannel()
        let sourceStream = EventStream<Int>(source: source)
        
        let testEvents = (0..<15).map { value in (value * value) + 2 }
        
        let expectedEvents = testEvents.indices
            .filter { index in index < testEvents.count - 1 }
            .map { index in testEvents[index + 1] - testEvents[index] }

        let differentiatedStream = sourceStream.difference(-)
        
        var receivedEvents = [Int]()
        
        let subscription = differentiatedStream.subscribe { event in receivedEvents.append(event) }
        
        for event in testEvents {
            source.publish(event)
        }
        
        XCTAssertEqual(receivedEvents, expectedEvents)
    }
    
    func testDebounce() throws {
        
        let source: AnyTypedChannel<String> = SimpleChannel().asTypedChannel()
        let sourceStream = EventStream<String>(source: source)
         
        var expectedEvents = [String]()

        let tolerance: TimeInterval = 0.25
        let debouncedStream = sourceStream.debounce(tolerance: tolerance)
        
        var receivedEvents = [String]()
        
        let subscription = debouncedStream.subscribe { event in receivedEvents.append(event) }
        
        for index in 0..<10 {
            
            let firstEvent = "Event \(index)"
            let secondEvent = "Echo \(index)"

            source.publish(firstEvent)
            source.publish(secondEvent)
            
            expectedEvents.append(firstEvent)
            
            Thread.sleep(forTimeInterval: tolerance)
        }

        XCTAssertEqual(receivedEvents, expectedEvents)
    }
}
