#import "ESHTTPOperation.h"

@class ESJSONOperation;
typedef void (^ESJSONOperationSuccessBlock)(ESJSONOperation *op, id JSON);
typedef void (^ESJSONOperationFailureBlock)(ESJSONOperation *op);

/**
 `ESJSONOperation` is an `NSOperation` that wraps the callback from `ESHTTPOperation` to determine the success or failure of a request based on its status code and response content type, and parse the response body into a JSON object.
 
 @see NSOperation
 @see ESHTTPOperation
 */

@interface ESJSONOperation (Deprecated)

///--------------------------
/// @name Creating Operations (Deprecated)
///--------------------------

/**
 Creates and returns an `ESJSONOperation` object and sets the specified success callback.
 
	typedef void (^ESJSONOperationSuccessBlock)(ESJSONOperation *op, id JSON);
 
 @param urlRequest The request object to be loaded asynchronously during execution of the operation
 @param success A block object to be executed when the JSON request operation finishes successfully, with a status code in the 2xx range, and with an acceptable content type (e.g. `application/json`). This block has no return value and takes a single argument, which is the JSON object created from the response data of request, or nil if there was an error.
 
 @see defaultAcceptableStatusCodes
 @see defaultAcceptableContentTypes
 @see operationWithRequest:success:failure:
 
 @return A new JSON request operation
 */
+ (instancetype)newJSONOperationWithRequest:(NSURLRequest *)urlRequest success:(ESJSONOperationSuccessBlock)success __attribute__((deprecated("Seperating success and failure blocks is weird and I don't know why I ever did it")));

/**
 Creates and returns an `ESJSONOperation` object and sets the specified success and failure callbacks.
 
	typedef void (^ESJSONOperationSuccessBlock)(ESJSONOperation *op, id JSON);
 
	typedef void (^ESJSONOperationFailureBlock)(ESJSONOperation *op);
 
 @param urlRequest The request object to be loaded asynchronously during execution of the operation
 @param success A block object to be executed when the JSON request operation finishes successfully, with a status code in the 2xx range, and with an acceptable content type (e.g. `application/json`). This block has no return value and takes a single argument, which is the JSON object created from the response data of request.
 @param failure A block object to be executed when the JSON request operation finishes unsuccessfully, or that finishes successfully, but encountered an error while parsing the resonse data as JSON. This block has no return value and takes a single argument, which is the error describing the network or parsing error that occurred.
 
 @see defaultAcceptableStatusCodes
 @see defaultAcceptableContentTypes
 @see operationWithRequest:success:
 
 @return A new JSON request operation
 */
+ (instancetype)newJSONOperationWithRequest:(NSURLRequest *)urlRequest success:(ESJSONOperationSuccessBlock)success failure:(ESJSONOperationFailureBlock)failure;

@end

// Based on https://github.com/gowalla/AFNetworking/blob/master/AFNetworking/AFJSONRequestOperation.h

// AFJSONRequestOperation.h
//
// Copyright (c) 2011 Gowalla (http://gowalla.com/)
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
