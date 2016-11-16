# Data Race Detector in Swift

This is a project I undertook for educational purposes. It aims to implement the algorithm of the data race detection in LLVM's Thread Sanitizer in Swift. 

While the actual Thread Sanitizer uses compile time instrumentation and a runtime library, this toy project is entirely implemented in Swift. To make this possible, the implementation provides an `ObservedValue<T>` type in which a value needs to be wrapped in order to be monitored for potential data races.

Additionally the libary provides its own mutex via the function `synchronized`. The data race detector only understands synchronization that happens through that function; synchronization by any other means cannot be tracked and will therefore lead to incorrectly reported data races.

Here's the [Google Research paper that describes the algorithm](http://static.googleusercontent.com/media/research.google.com/en//pubs/archive/35604.pdf) for data race detection in Thread Sanitizer and [here's an Apple WWDC 2016 session that discusses the algorithm as well](https://developer.apple.com/videos/play/wwdc2016/412/?time=993).

