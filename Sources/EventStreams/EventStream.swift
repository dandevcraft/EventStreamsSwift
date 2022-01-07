//
// Created by Daniel Coleman on 11/18/21.
//

import Foundation
import Observer

public protocol EventStreamProtocol {

    associatedtype Payload

    func subscribe(_ handler: @escaping (Payload) -> Void) -> Subscription
}

final public class EventStream<Payload> : EventStreamProtocol {

    fileprivate init() {

        self.channel = SimpleChannel().asTypedChannel()
    }

    public convenience init<Source: TypedChannel>(source: Source) where Source.Event == Payload {

        self.init()
        
        source.subscribe { [weak self] event in self?.publish(event) }
            .store(in: &subscriptions)
    }

    public func subscribe(_ handler: @escaping (Payload) -> Void) -> Subscription {

        subscribeWithTime { event in handler(event.payload) }
    }

    fileprivate func subscribeWithTime(_ handler: @escaping (Event) -> Void) -> Subscription {

        channel.subscribe(handler)
    }
    
    fileprivate func publish(_ payload: Payload) {

        publish((payload: payload, time: Date()))
    }

    fileprivate func publish(_ event: Event) {

        channel.publish(event)
    }

    fileprivate typealias Event = (payload: Payload, time: Date)
    
    fileprivate let channel: AnyTypedChannel<Event>
    fileprivate var subscriptions = Set<Subscription>()
}

extension EventStream {

    public func filter(_ condition: @escaping (Payload) -> Bool) -> EventStream<Payload> {

        filter { payload, date in
            
            condition(payload)
        }
    }

    public func filter(_ condition: @escaping (Payload, Date) -> Bool) -> EventStream<Payload> {

        let stream = EventStream<Payload>()

        stream.subscriptions.insert(subscribeWithTime { event in

            if condition(event.payload, event.time) {
                stream.publish(event)
            }
        })

        return stream
    }
}

extension EventStream {

    public func map<Result>(_ transform: @escaping (Payload) -> Result) -> EventStream<Result> {

        map { payload, date in
            
            transform(payload)
        }
    }
    
    public func map<Result>(_ transform: @escaping (Payload, Date) -> Result) -> EventStream<Result> {

        let stream = EventStream<Result>()

        stream.subscriptions.insert(subscribeWithTime { (payload, time) in stream.publish(transform(payload, time)) })

        return stream
    }
}

extension EventStream where Payload : EventStreamProtocol {

    public func flatten() -> EventStream<Payload.Payload> {

        let stream = EventStream<Payload.Payload>()

        stream.subscriptions.insert(subscribe { innerStream in

            stream.subscriptions.insert(innerStream.subscribe(stream.publish))
        })

        return stream
    }
}

extension EventStream {

    public func flatMap<Result>(_ transform: @escaping (Payload) -> EventStream<Result>) -> EventStream<Result> {

        flatMap { payload, date in
            
            transform(payload)
        }
    }
    
    public func flatMap<Result>(_ transform: @escaping (Payload, Date) -> EventStream<Result>) -> EventStream<Result> {

        self
            .map(transform)
            .flatten()
    }
}

extension EventStream where Payload : EventStreamProtocol {

    public func `switch`() -> EventStream<Payload.Payload> {

        let stream = EventStream<Payload.Payload>()

        var innerSubscription: Subscription?

        stream.subscriptions.insert(subscribe { innerStream in

            if let subscription = innerSubscription {
                stream.subscriptions.remove(subscription)
            }

            let newSubscription = innerStream.subscribe(stream.publish)
            stream.subscriptions.insert(newSubscription)
            innerSubscription = newSubscription
        })

        return stream
    }
}

extension EventStream {

    public func switchMap<Result>(_ transform: @escaping (Payload) -> EventStream<Result>) -> EventStream<Result> {

        self
            .map(transform)
            .switch()
    }
}

extension Collection where Element : EventStreamProtocol {

    public func merge() -> EventStream<Element.Payload> {

        let stream = EventStream<Element.Payload>()

        for element in self {
            stream.subscriptions.insert(element.subscribe(stream.publish))
        }

        return stream
    }
}

extension EventStream {

    public func merge(_ other: EventStream<Payload>) -> EventStream<Payload> {

        return [self, other].merge()
    }
}

extension EventStream {

    public func combineLatest<Other>(
        _ other: EventStream<Other>
    ) -> EventStream<(Payload, Other)> {

        var first: Payload?
        var second: Other?

        let stream = EventStream<(Payload, Other)>()

        let send: () -> Void = {

            if let f = first, let s = second {
                stream.publish((f, s))
            }
        }

        stream.subscriptions.insert(subscribe { event in

            first = event
            send()
        })

        stream.subscriptions.insert(other.subscribe { event in

            second = event
            send()
        })

        return stream
    }

    public func combineLatest<Other1, Other2>(
        _ other1: EventStream<Other1>,
        _ other2: EventStream<Other2>
    ) -> EventStream<(Payload, Other1, Other2)> {

        self
            .combineLatest(other1)
            .combineLatest(other2)
            .map { first, last in (first.0, first.1, last) }
    }

    public func combineLatest<Other1, Other2, Other3>(
        _ other1: EventStream<Other1>,
        _ other2: EventStream<Other2>,
        _ other3: EventStream<Other3>
    ) -> EventStream<(Payload, Other1, Other2, Other3)> {

        self
            .combineLatest(other1, other2)
            .combineLatest(other3)
            .map { first, last in (first.0, first.1, first.2, last) }
    }

    public func combineLatest<Other1, Other2, Other3, Other4>(
        _ other1: EventStream<Other1>,
        _ other2: EventStream<Other2>,
        _ other3: EventStream<Other3>,
        _ other4: EventStream<Other4>
    ) -> EventStream<(Payload, Other1, Other2, Other3, Other4)> {

        self
            .combineLatest(other1, other2, other3)
            .combineLatest(other4)
            .map { first, last in (first.0, first.1, first.2, first.3, last) }
    }
}

extension EventStream {

    public func zip<Other>(
        _ other: EventStream<Other>
    ) -> EventStream<(Payload, Other)> {

        var first: Payload?
        var second: Other?

        let stream = EventStream<(Payload, Other)>()

        let send: () -> Void = {

            if let f = first, let s = second {
                stream.publish((f, s))
                
                first = nil
                second = nil
            }
        }

        stream.subscriptions.insert(subscribe { event in

            first = event
            send()
        })

        stream.subscriptions.insert(other.subscribe { event in

            second = event
            send()
        })

        return stream
    }

    public func zip<Other1, Other2>(
        _ other1: EventStream<Other1>,
        _ other2: EventStream<Other2>
    ) -> EventStream<(Payload, Other1, Other2)> {

        self
            .zip(other1)
            .zip(other2)
            .map { first, last in (first.0, first.1, last) }
    }

    public func zip<Other1, Other2, Other3>(
        _ other1: EventStream<Other1>,
        _ other2: EventStream<Other2>,
        _ other3: EventStream<Other3>
    ) -> EventStream<(Payload, Other1, Other2, Other3)> {

        self
            .zip(other1, other2)
            .zip(other3)
            .map { first, last in (first.0, first.1, first.2, last) }
    }

    public func zip<Other1, Other2, Other3, Other4>(
        _ other1: EventStream<Other1>,
        _ other2: EventStream<Other2>,
        _ other3: EventStream<Other3>,
        _ other4: EventStream<Other4>
    ) -> EventStream<(Payload, Other1, Other2, Other3, Other4)> {

        self
            .zip(other1, other2, other3)
            .zip(other4)
            .map { first, last in (first.0, first.1, first.2, first.3, last) }
    }
}

extension EventStream {

    public func buffer(count: Int, stride: Int) -> EventStream<[Payload]> {

        let stream = EventStream<[Payload]>()

        let skip = max(stride - count, 0)
        
        var items: [Payload] = []
        var toSkip = 0

        stream.subscriptions.insert(subscribe { event in

            if toSkip > 0 {
                toSkip -= 1
                return
            }
            
            items.append(event)

            if items.count < count {
                return
            }

            stream.publish(items)

            items.removeFirst(min(stride, items.count))
            toSkip = skip
        })

        return stream
    }
}

extension EventStream {

    public func accumulate<Result>(
        initialValue: Result,
        publishInitial: Bool = false,
        _ accumulator: @escaping (Result, Payload) -> Result
    ) -> EventStream<Result> {

        let stream = EventStream<Result>()

        var last = initialValue
        if publishInitial {
            stream.publish(last)
        }

        stream.subscriptions.insert(subscribe { event in

            last = accumulator(last, event)
            stream.publish(last)
        })

        return stream
    }
}

extension EventStream {

    public func difference<Result>(
        _ differentiator: @escaping (Payload, Payload) -> Result
    ) -> EventStream<Result> {

        let stream = EventStream<Result>()

        var lastOpt: Payload?

        stream.subscriptions.insert(subscribe { payload in

            if let last = lastOpt {
                stream.publish(differentiator(payload, last))
            }
            
            lastOpt = payload
        })

        return stream
    }
}

extension EventStream {

    public func debounce(tolerance: TimeInterval) -> EventStream<Payload> {

        var lastTime = Date(timeIntervalSince1970: 0)

        return self.filter { payload, time in
            
            let timeInterval = time.timeIntervalSince(lastTime)
            lastTime = time

            return timeInterval >= tolerance
        }
    }
}
