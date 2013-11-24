#import "ESHTTPOperation.h"
#import <libkern/OSAtomic.h>

NSString * kESHTTPOperationErrorDomain = @"ESHTTPOperationErrorDomain";

@interface ESHTTPOperation ()
{
@private
	NSMutableIndexSet *_acceptableStatusCodes;
	NSRecursiveLock *_acceptableStatusCodesLock;
	NSMutableSet *_acceptableContentTypes;
	NSRecursiveLock *_acceptableContentTypesLock;
	NSRecursiveLock *_completionQueueLock;
	NSRecursiveLock *_workQueueLock;
}
+ (void)networkRunLoopThreadEntry __attribute__ ((noreturn));
+ (NSThread *)networkRunLoopThread;
@property (copy, nonatomic) ESHTTPOperationWorkBlock work;
@property (copy, nonatomic) ESHTTPOperationCompletionBlock completion;
@property (copy, nonatomic) ESHTTPOperationUploadBlock uploadProgress;
@property (copy, nonatomic) ESHTTPOperationDownloadBlock downloadProgress;
@property id processedResponse;
- (void)processRequest:(NSError *)error;
@end

@implementation ESHTTPOperation
@synthesize defaultResponseSize=_defaultResponseSize;
@synthesize maximumResponseSize=_maximumResponseSize;
@synthesize outputStream=_outputStream;
@synthesize completionQueue=_completionQueue;
@synthesize workQueue=_workQueue;

static NSThread *_networkRunLoopThread = nil;

+ (void)networkRunLoopThreadEntry
// This thread runs all of our network operation run loop callbacks.
{
	NSAssert(([NSThread currentThread] == [[self class] networkRunLoopThread]), @"Entered networkRunLoopThreadEntry from invalid thread");	
	@autoreleasepool {
		// Schedule a timer in the distant future to keep the run loop from simply immediately exiting
		[NSTimer scheduledTimerWithTimeInterval:3600*24*365*100 target:nil selector:nil userInfo:nil repeats:NO];
		while (YES) 
		{
			@autoreleasepool {
				CFRunLoopRunInMode(kCFRunLoopDefaultMode, 10, YES);
			}
		}
	}
	NSAssert(NO, @"Exited networkRunLoopThreadEntry prematurely");
}

+ (NSThread *)networkRunLoopThread
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		// We run all of our network callbacks on a secondary thread to ensure that they don't
		// contribute to main thread latency. Create and configure that thread.
		_networkRunLoopThread = [[NSThread alloc] initWithTarget:[self class] selector:@selector(networkRunLoopThreadEntry) object:nil];
		NSParameterAssert(_networkRunLoopThread != nil);
		[_networkRunLoopThread setThreadPriority:0.3];
		[_networkRunLoopThread setName:@"ESNetworkingRunLoopThread"];
		[_networkRunLoopThread start];
	});
	return _networkRunLoopThread;
}

static int32_t _globalOperationIDCounter = 10000;
static int32_t GetOperationID(void)
{
	return OSAtomicIncrement32(&_globalOperationIDCounter);;
}

#pragma mark - Init / Dealloc

+ (instancetype)newHTTPOperationWithRequest:(NSURLRequest *)request work:(ESHTTPOperationWorkBlock)work completion:(ESHTTPOperationCompletionBlock)completion
{
	return [[[self class] alloc] initWithRequest:request work:(ESHTTPOperationWorkBlock)work completion:completion];
}

- (instancetype)initWithRequest:(NSURLRequest *)request work:(ESHTTPOperationWorkBlock)work completion:(ESHTTPOperationCompletionBlock)completion
// See comment in header.
{
	// any thread
	NSParameterAssert(request != nil);
	NSParameterAssert([request URL] != nil);
	// Because we require an NSHTTPURLResponse, we only support HTTP and HTTPS URLs.
	NSParameterAssert([[[[request URL] scheme] lowercaseString] isEqual:@"http"] || [[[[request URL] scheme] lowercaseString] isEqual:@"https"]);
	self = [super init];
	if ((request == nil) || ([request URL] == nil))
	{
		self = nil;
	}
	if (self != nil)
	{
		_completion = [completion copy];
		_work = [work copy];
		_request = [request copy];
		_defaultResponseSize = 1 * 1024 * 1024;
		_maximumResponseSize = 4 * 1024 * 1024;
		_firstData = YES;
		_operationID = GetOperationID();
		_acceptableStatusCodesLock = [NSRecursiveLock new];
		_acceptableContentTypesLock = [NSRecursiveLock new];
		_completionQueueLock = [NSRecursiveLock new];
		_workQueueLock = [NSRecursiveLock new];
	}
	return self;
}

#pragma mark - State Check

- (void)confirmSelectorCalledInInitStateOrThrowException:(SEL)selector
{
	NSParameterAssert(selector);
	ESOperationState state = self.state;
	if (state != kESOperationStateInited)
	{
		[NSException raise:@"Invalid State Exception" format:@"Attempted %@ while in state: %d. May only be attempted prior to queueing operation.", NSStringFromSelector(selector), state];
	}
}

#pragma mark - Queues

- (NSOperationQueue *)completionQueue
{
	[_completionQueueLock lock];
	NSOperationQueue *queue;
	if (_completionQueue)
	{
		queue = _completionQueue;
	}
	else
	{
		queue = [NSOperationQueue mainQueue];
	}
	[_completionQueueLock unlock];
	return queue;
}

- (void)setCompletionQueue:(NSOperationQueue *)completionQueue
{
	[self confirmSelectorCalledInInitStateOrThrowException:_cmd];
	{
		[_completionQueueLock lock];
		if (_completionQueue != completionQueue)
		{
			_completionQueue = completionQueue;
		}
		[_completionQueueLock unlock];
	}
}

- (NSOperationQueue *)workQueue
{
	[_workQueueLock lock];
	NSOperationQueue *queue;
	if (_workQueue)
	{
		queue = _workQueue;
	}
	else
	{
		static NSOperationQueue *_processingQueue;
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			_processingQueue = [NSOperationQueue new];
			_processingQueue.name = @"com.es.processing_queue";
		});
		queue = _processingQueue;
	}
	[_workQueueLock unlock];
	return queue;
}

- (void)setWorkQueue:(NSOperationQueue *)workQueue
{
	[self confirmSelectorCalledInInitStateOrThrowException:_cmd];
	{
		[_workQueueLock lock];
		if (_workQueue != workQueue)
		{
			_workQueue = workQueue;
		}
		[_workQueueLock unlock];
	}
}

#pragma mark - Start and finish overrides

- (void)operationDidStart
// Called by QRunLoopOperation when the operation starts. This kicks of an
// asynchronous NSURLConnection.
{
	NSParameterAssert(self.isActualRunLoopThread);
	NSParameterAssert(self.state == kESOperationStateExecuting);
	NSParameterAssert(self.defaultResponseSize > 0);
	NSParameterAssert(self.maximumResponseSize > 0);
	NSParameterAssert(self.defaultResponseSize <= self.maximumResponseSize);
	NSParameterAssert(self.request != nil);
	// Create a connection that's scheduled in the required run loop modes.
	NSParameterAssert(self.connection == nil);
	NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:self.request delegate:self startImmediately:NO];
	self.connection = connection;
	NSParameterAssert(self.connection != nil);
	for (NSString * mode in self.actualRunLoopModes)
	{
		[self.connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:mode];
	}
	[self.connection start];
}

- (void)operationWillFinish
// Called by ESRunLoopOperation when the operation has finished. We
// do various bits of tidying up.
{
	NSParameterAssert(self.isActualRunLoopThread);
	NSParameterAssert(self.state == kESOperationStateExecuting);
	[self.connection cancel];
	self.connection = nil;
	// If we have an output stream, close it at this point.	 We might never
	// have actually opened this stream but, AFAICT, closing an unopened stream
	// doesn't hurt.
	if (self.outputStream != nil)
	{
		[self.outputStream close];
	}
}

- (void)processRequest:(NSError *)error
{
	if (error)
	{
		[self finishWithError:error];
	}
	else if (self.work)
	{
		[self.workQueue addOperationWithBlock:^{
			NSError *error = nil;
			id result = self.work(self, &error);
			if (!error && result)
			{
				self.processedResponse = result;
			}
			if (self.state == kESOperationStateExecuting)
			{
				[self performSelector:@selector(finishWithError:) onThread:self.actualRunLoopThread withObject:error waitUntilDone:NO];
			}
		}];
	}
	else
	{
		[self finishWithError:nil];
	}
}

- (BOOL)finishWithError:(NSError *)error
{
	if (![super finishWithError:error])
	{
		return NO;
	}
	void (^cleanup)(void) = ^{
		self.completion = nil;
		self.work = nil;
		self.uploadProgress = nil;
		self.downloadProgress = nil;
	};
	ESHTTPOperationCompletionBlock completion = self.completion;
	if (completion)
	{
		[self.completionQueue addOperationWithBlock:^{
			completion(self);
			cleanup();
		}];
	}
	else
	{
		cleanup();
	}
	return YES;
}

#pragma mark - NSURLConnection Delegate

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response
// See comment in header.
{
	NSParameterAssert(self.isActualRunLoopThread);
	NSParameterAssert(connection == self.connection);
#if defined(NS_BLOCK_ASSERTIONS)
#pragma unused(connection)
#endif
	NSParameterAssert( (response == nil) || [response isKindOfClass:[NSHTTPURLResponse class]] );
	self.lastRequest = request;
	self.lastResponse = (NSHTTPURLResponse *)response;
	return request;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
// See comment in header.
{
	NSParameterAssert(self.isActualRunLoopThread);
	NSParameterAssert(connection == self.connection);
#if defined(NS_BLOCK_ASSERTIONS)
#pragma unused(connection)
#endif
	NSParameterAssert([response isKindOfClass:[NSHTTPURLResponse class]]);
	self.totalBytesWritten = 0;
	self.lastResponse = (NSHTTPURLResponse *)response;
	if (self.cancelOnStatusCodeError && !self.isStatusCodeAcceptable)
	{
		[self.connection cancel];
		self.connection = nil;
		[self processRequest:[self errorForStatusCode]];
	}
	else if (self.cancelOnContentTypeError && ![self isContentTypeAcceptable])
	{
		[self.connection cancel];
		self.connection = nil;
		[self processRequest:[self errorForContentType]];
	}
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
// See comment in header.
{
	BOOL success;
	NSParameterAssert(self.isActualRunLoopThread);
	NSParameterAssert(connection == self.connection);
#if defined(NS_BLOCK_ASSERTIONS)
#pragma unused(connection)
#endif
	NSParameterAssert(data != nil);
	// If we don't yet have a destination for the data, calculate one.	Note that, even
	// if there is an output stream, we don't use it for error responses.
	success = YES;
	if (self.firstData)
	{
		NSParameterAssert(self.dataAccumulator == nil);
		if ((self.outputStream == nil) || !self.isStatusCodeAcceptable)
		{
			long long length;
			NSParameterAssert(self.dataAccumulator == nil);
			length = [self.lastResponse expectedContentLength];
			if (length == NSURLResponseUnknownLength)
			{
				length = self.defaultResponseSize;
			}
			if (length <= (long long)self.maximumResponseSize)
			{
				self.dataAccumulator = [NSMutableData dataWithCapacity:(NSUInteger)length];
			}
			else
			{
				[self processRequest:[NSError errorWithDomain:kESHTTPOperationErrorDomain code:kESHTTPOperationErrorResponseTooLarge userInfo:nil]];
				success = NO;
			}
		}
		// If the data is going to an output stream, open it.
		if (success)
		{
			if (self.dataAccumulator == nil)
			{
				NSParameterAssert(self.outputStream != nil);
				[self.outputStream open];
			}
		}
		self.firstData = NO;
	}
	// Write the data to its destination.
	if (success)
	{
		if (self.dataAccumulator != nil)
		{
			ESHTTPOperationDownloadBlock downloadProgress = self.downloadProgress;
			if (downloadProgress)
			{
				NSUInteger totalBytes = [self.dataAccumulator length] + [data length];
				NSUInteger totalBytesExpected = (NSUInteger)[self.lastResponse expectedContentLength];
				dispatch_async(dispatch_get_main_queue(), ^{
					downloadProgress(totalBytes, totalBytesExpected);
				});
			}
			if (([self.dataAccumulator length] + [data length]) <= self.maximumResponseSize)
			{
				[self.dataAccumulator appendData:data];
			}
			else
			{
				[self processRequest:[NSError errorWithDomain:kESHTTPOperationErrorDomain code:kESHTTPOperationErrorResponseTooLarge userInfo:nil]];
			}
		}
		else
		{
			NSParameterAssert(self.outputStream != nil);
			
			NSUInteger dataOffset = 0;
			NSUInteger dataLength = [data length];
			const uint8_t *dataPtr = [data bytes];
			NSError *error = nil;
			NSInteger bytesWritten;
			do
			{
				if (dataOffset == dataLength)
				{
					break;
				}
				bytesWritten = [self.outputStream write:&dataPtr[dataOffset] maxLength:dataLength - dataOffset];
				if (bytesWritten <= 0)
				{
					error = [self.outputStream streamError];
					if (error == nil)
					{
						error = [NSError errorWithDomain:kESHTTPOperationErrorDomain code:kESHTTPOperationErrorOnOutputStream userInfo:nil];
					}
					break;
				}
				else
				{
					dataOffset += bytesWritten;
					self.totalBytesWritten += bytesWritten;
				}
			}
			while (YES);
			
			ESHTTPOperationDownloadBlock downloadProgress = self.downloadProgress;
			if (downloadProgress) 
			{
				NSUInteger totalBytes = self.totalBytesWritten;
				NSUInteger totalBytesExpected = (NSUInteger)[self.lastResponse expectedContentLength];
				dispatch_async(dispatch_get_main_queue(), ^{
					downloadProgress(totalBytes, totalBytesExpected);
				});
			}
			if (error != nil)
			{
				[self processRequest:error];
			}
		}
	}
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
// See comment in header.
{
	NSParameterAssert(self.isActualRunLoopThread);
	NSParameterAssert(connection == self.connection);
#if defined(NS_BLOCK_ASSERTIONS)
#pragma unused(connection)
#endif
	NSParameterAssert(self.lastResponse != nil);
	// Swap the data accumulator over to the response data so that we don't trigger a copy.
	NSParameterAssert(_responseBody == nil);
	_responseBody = _dataAccumulator;
	_dataAccumulator = nil;
	// Because we fill out _dataAccumulator lazily, an empty body will leave _dataAccumulator
	// set to nil.	That's not what our clients expect, so we fix it here.
	if (_responseBody == nil)
	{
		_responseBody = [[NSData alloc] init];
		NSParameterAssert(_responseBody != nil);
	}
	if (!self.isStatusCodeAcceptable)
	{
		[self processRequest:[self errorForStatusCode]];
	}
	else if (!self.isContentTypeAcceptable)
	{
		[self processRequest:[self errorForContentType]];
	}
	else
	{
		[self processRequest:nil];
	}
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
// See comment in header.
{
	NSParameterAssert(self.isActualRunLoopThread);
	NSParameterAssert(connection == self.connection);
#if defined(NS_BLOCK_ASSERTIONS)
#pragma unused(connection)
#endif
	NSParameterAssert(error != nil);
	[self processRequest:error];
}

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
	ESHTTPOperationUploadBlock uploadProgress = self.uploadProgress;
	if (uploadProgress)
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			uploadProgress(totalBytesWritten, totalBytesExpectedToWrite);
		});
	}
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse 
{
	if ([self isCancelled])
	{
		return nil;
	}
	return cachedResponse;
}

#pragma mark - Properties

//	
//	Several properties enforce state because they are nonatomic and
//	it is unsafe to manipulate them after the operation has been
//	queued.
//	
//	Making them atomic would mean locking that wouldn't be
//	necessary in most use cases.
//	

- (NSThread *)actualRunLoopThread
// Returns the effective run loop thread, that is, the one set by the user 
// or, if that's not set, the network thread.
{
	NSThread *result;
	result = self.runLoopThread;
	if (result == nil)
	{
		result = [[self class] networkRunLoopThread];
	}
	return result;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ : %p>\n{\n\tRequest: %@\n\tResponse: %@\n\tID: %d\n\tError: %@\n}", NSStringFromClass([self class]), self, self.request, self.lastResponse, (int)self.operationID, self.error];
}

- (void)setUploadProgressBlock:(ESHTTPOperationUploadBlock)uploadProgress
{
	if (self.state != kESOperationStateInited)
	{
		[NSException raise:@"Set Upload Progress Block in Invalid State" format:@"Attempted to setUploadProgressBlock while in state: %d. UploadProgressBlock may only be set prior to queueing operation", self.state];
	}
	self.uploadProgress = uploadProgress;
}

- (void)setDownloadProgressBlock:(ESHTTPOperationDownloadBlock)downloadProgress
{
	[self confirmSelectorCalledInInitStateOrThrowException:_cmd];
	self.downloadProgress = downloadProgress;
}

+ (BOOL)automaticallyNotifiesObserversOfAcceptableStatusCodes
{
	return NO;
}

- (NSIndexSet *)acceptableStatusCodes
{
	[_acceptableStatusCodesLock lock];
	NSIndexSet *acceptableStatusCodes;
	if (_acceptableStatusCodes != nil)
	{
		acceptableStatusCodes = _acceptableStatusCodes;
	}
	else
	{
		[self willChangeValueForKey:@"acceptableStatusCodes"];
		_acceptableStatusCodes = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 100)];
		[self didChangeValueForKey:@"acceptableStatusCodes"];
		acceptableStatusCodes = _acceptableStatusCodes;
	}
	[_acceptableStatusCodesLock unlock];
	return acceptableStatusCodes;
}

- (void)setAcceptableStatusCodes:(NSIndexSet *)newValue
{
	[self confirmSelectorCalledInInitStateOrThrowException:_cmd];
	{
		[_acceptableStatusCodesLock lock];
		if (newValue != _acceptableStatusCodes)
		{
			[self willChangeValueForKey:@"acceptableStatusCodes"];
			_acceptableStatusCodes = [newValue mutableCopy];
			[self didChangeValueForKey:@"acceptableStatusCodes"];
		}
		[_acceptableStatusCodesLock unlock];
	}
}

- (void)addAcceptableStatusCode:(NSUInteger)statusCode
{
	[self confirmSelectorCalledInInitStateOrThrowException:_cmd];
	[_acceptableStatusCodesLock lock];
	NSMutableIndexSet *statusCodes = (NSMutableIndexSet *)self.acceptableStatusCodes;
	[statusCodes addIndex:statusCode];
	[_acceptableStatusCodesLock unlock];
}

- (void)removeAcceptableStatusCode:(NSUInteger)statusCode
{
	[self confirmSelectorCalledInInitStateOrThrowException:_cmd];
	[_acceptableStatusCodesLock lock];
	NSMutableIndexSet *statusCodes = (NSMutableIndexSet *)self.acceptableStatusCodes;
	[statusCodes removeIndex:statusCode];
	[_acceptableStatusCodesLock unlock];
}

+ (BOOL)automaticallyNotifiesObserversOfAcceptableContentTypes
{
	return NO;
}

- (NSSet *)acceptableContentTypes
{
	[_acceptableContentTypesLock lock];
	NSSet *acceptableContentTypes;
	if (_acceptableContentTypes != nil)
	{
		acceptableContentTypes = _acceptableContentTypes;
	}
	else
	{
		[self willChangeValueForKey:@"acceptableContentTypes"];
		_acceptableContentTypes = [NSMutableSet set];
		[self didChangeValueForKey:@"acceptableContentTypes"];
		acceptableContentTypes = _acceptableContentTypes;
	}
	[_acceptableContentTypesLock unlock];
	return acceptableContentTypes;
}

- (void)setAcceptableContentTypes:(NSSet *)newValue
{
	[self confirmSelectorCalledInInitStateOrThrowException:_cmd];
	{
		[_acceptableContentTypesLock lock];
		if (newValue != _acceptableContentTypes)
		{
			[self willChangeValueForKey:@"acceptableContentTypes"];
			_acceptableContentTypes = [newValue copy];
			[self didChangeValueForKey:@"acceptableContentTypes"];
		}
		[_acceptableContentTypesLock unlock];
	}
}

- (void)addAcceptableContentType:(NSString *)contentType
{
	[self confirmSelectorCalledInInitStateOrThrowException:_cmd];
	if (contentType == nil)
	{
		return;
	}
	[_acceptableContentTypesLock lock];
	NSMutableSet *acceptableContentType = (NSMutableSet *)self.acceptableContentTypes;
	[acceptableContentType addObject:contentType];
	[_acceptableContentTypesLock unlock];
}

- (void)removeAcceptableContentType:(NSString *)contentType
{
	[self confirmSelectorCalledInInitStateOrThrowException:_cmd];
	if (contentType == nil)
	{
		return;
	}
	[_acceptableContentTypesLock lock];
	NSMutableSet *acceptableContentType = (NSMutableSet *)self.acceptableContentTypes;
	[acceptableContentType removeObject:contentType];
	[_acceptableContentTypesLock unlock];
}

+ (BOOL)automaticallyNotifiesObserversOfOutputStream
{
	return NO;
}

- (NSOutputStream *)outputStream
{
	return _outputStream;
}

- (void)setOutputStream:(NSOutputStream *)newValue
{
	if (self.dataAccumulator != nil)
	{
		NSParameterAssert(NO);
	}
	else
	{
		if (newValue != _outputStream)
		{
			[self willChangeValueForKey:@"outputStream"];
			_outputStream = newValue;
			[self didChangeValueForKey:@"outputStream"];
		}
	}
}

+ (BOOL)automaticallyNotifiesObserversOfDefaultResponseSize
{
	return NO;
}

- (NSUInteger)defaultResponseSize
{
	return _defaultResponseSize;
}

- (void)setDefaultResponseSize:(NSUInteger)newValue
{
	if (self.dataAccumulator != nil)
	{
		NSParameterAssert(NO);
	}
	else
	{
		if (newValue != _defaultResponseSize)
		{
			[self willChangeValueForKey:@"defaultResponseSize"];
			_defaultResponseSize = newValue;
			[self didChangeValueForKey:@"defaultResponseSize"];
		}
	}
}

+ (BOOL)automaticallyNotifiesObserversOfMaximumResponseSize
{
	return NO;
}

- (NSUInteger)maximumResponseSize
{
	return _maximumResponseSize;
}

- (void)setMaximumResponseSize:(NSUInteger)newValue
{
	if (self.dataAccumulator != nil)
	{
		NSParameterAssert(NO);
	}
	else
	{
		if (newValue != _maximumResponseSize)
		{
			[self willChangeValueForKey:@"maximumResponseSize"];
			_maximumResponseSize = newValue;
			[self didChangeValueForKey:@"maximumResponseSize"];
		}
	}
}

- (NSURL *)URL
{
	return [self.request URL];
}

- (BOOL)isStatusCodeAcceptable
{
	NSIndexSet *acceptableStatusCodes;
	NSInteger statusCode;
	NSParameterAssert(self.lastResponse != nil);
	acceptableStatusCodes = self.acceptableStatusCodes;
	NSParameterAssert(acceptableStatusCodes != nil);
	statusCode = [self.lastResponse statusCode];
	return (statusCode >= 0) && [acceptableStatusCodes containsIndex:(NSUInteger)statusCode];
}

- (BOOL)isContentTypeAcceptable
{
	NSString*  contentType;
	NSParameterAssert(self.lastResponse != nil);
	contentType = [self.lastResponse MIMEType];
	NSSet *acceptableContentTypes = self.acceptableContentTypes;
	return ((acceptableContentTypes == nil) || (acceptableContentTypes.count == 0) || ((contentType != nil) && [acceptableContentTypes containsObject:contentType]));
}

#pragma mark - Errors

- (NSError *)errorForStatusCode
{
	NSDictionary *userInfo = @{
		NSUnderlyingErrorKey : [NSError errorWithDomain:kESHTTPOperationErrorDomain code:self.lastResponse.statusCode userInfo:nil],
		NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Expected status code in set %@, got %ld", nil), self.acceptableStatusCodes, (long)[self.lastResponse statusCode]],
	};
	NSError *error = [NSError errorWithDomain:kESHTTPOperationErrorDomain code:kESHTTPOperationErrorBadStatusCode userInfo:userInfo];
	return error;
}

- (NSError *)errorForContentType
{
	NSDictionary *userInfo = @{
		NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Expected content type in set %@, got %@", nil), self.acceptableContentTypes, [self.lastResponse MIMEType]],
	};
	NSError *error = [NSError errorWithDomain:kESHTTPOperationErrorDomain code:kESHTTPOperationErrorBadContentType userInfo:userInfo];
	return error;
}

@end

/*
 (http://developer.apple.com/library/ios/#samplecode/MVCNetworking/Listings/Networking_QHTTPOperation_h.html#//apple_ref/doc/uid/DTS40010443-Networking_QHTTPOperation_h-DontLinkElementID_26)
 QHTTPOperation is a general purpose NSOperation that runs an HTTP request. 
 You initialise it with an HTTP request and then, when you run the operation, 
 it sends the request and gathers the response.  It is quite a complex 
 object because it handles a wide variety of edge cases, but it's very 
 easy to use in simple cases:
 
 1. create the operation with the URL you want to get
 
 op = [[[QHTTPOperation alloc] initWithURL:url] autorelease];
 
 2. set up any non-default parameters, for example, set which HTTP 
 content types are acceptable
 
 op.acceptableContentTypes = [NSSet setWithObject:@"text/html"];
 
 3. enqueue the operation
 
 [queue addOperation:op];
 
 4. finally, when the operation is done, use the lastResponse and 
 error properties to find out how things went
 
 As mentioned above, QHTTPOperation is very general purpose.  There are a 
 large number of configuration and result options available to you.
 
 o You can specify a NSURLRequest rather than just a URL.
 
 o You can configure the run loop and modes on which the NSURLConnection is 
 scheduled.
 
 o You can specify what HTTP status codes and content types are OK.
 
 o You can set an authentication delegate to handle authentication challenges.
 
 o You can accumulate responses in memory or in an NSOutputStream. 
 
 o For in-memory responses, you can specify a default response size 
 (used to size the response buffer) and a maximum response size 
 (to prevent unbounded memory use).
 
 o You can get at the last request and the last response, to track 
 redirects.
 
 o There are a variety of funky debugging options to simulator errors 
 and delays.
 
 Finally, it's perfectly reasonable to subclass QHTTPOperation to meet you 
 own specific needs.  Specifically, it's common for the subclass to 
 override -connection:didReceiveResponse: in order to setup the output 
 stream based on the specific details of the response.
 */

/*
 File:       QHTTPOperation.m
 
 Contains:   An NSOperation that runs an HTTP request.
 
 Written by: DTS
 
 Copyright:  Copyright (c) 2010 Apple Inc. All Rights Reserved.
 
 Disclaimer: IMPORTANT: This Apple software is supplied to you by Apple Inc.
 ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or
 redistribution of this Apple software constitutes acceptance of
 these terms.  If you do not agree with these terms, please do
 not use, install, modify or redistribute this Apple software.
 
 In consideration of your agreement to abide by the following
 terms, and subject to these terms, Apple grants you a personal,
 non-exclusive license, under Apple's copyrights in this
 original Apple software (the "Apple Software"), to use,
 reproduce, modify and redistribute the Apple Software, with or
 without modifications, in source and/or binary forms; provided
 that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the
 following text and disclaimers in all such redistributions of
 the Apple Software. Neither the name, trademarks, service marks
 or logos of Apple Inc. may be used to endorse or promote
 products derived from the Apple Software without specific prior
 written permission from Apple.  Except as expressly stated in
 this notice, no other rights or licenses, express or implied,
 are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or
 by other works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis. 
 APPLE MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING
 WITHOUT LIMITATION THE IMPLIED WARRANTIES OF NON-INFRINGEMENT,
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, REGARDING
 THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
 COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT,
 INCIDENTAL OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) ARISING IN ANY WAY
 OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR DISTRIBUTION
 OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY
 OF CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY OR
 OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE POSSIBILITY OF
 SUCH DAMAGE.
 
 */

//
//  ESHTTPOperation.m
//
//  Created by Doug Russell
//  Copyright (c) 2011 Doug Russell. All rights reserved.
//  
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  
//  http://www.apache.org/licenses/LICENSE-2.0
//  
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//  
