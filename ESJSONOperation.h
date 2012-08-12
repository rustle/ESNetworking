#import "ESHTTPOperation.h"

@class ESJSONOperation;
typedef void (^ESJSONOperationSuccessBlock)(ESJSONOperation *op, id JSON);
typedef void (^ESJSONOperationFailureBlock)(ESJSONOperation *op);

/**
 `ESJSONOperation` is an `NSOperation` that wraps the callback from `ESHTTPOperation` to determine the success or failure of a request based on its status code and response content type, and parse the response body into a JSON object.
 
 @see NSOperation
 @see ESHTTPOperation
 */

@interface ESJSONOperation : ESHTTPOperation

///--------------------------
/// @name Creating Operations
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
+ (instancetype)newJSONOperationWithRequest:(NSURLRequest *)urlRequest success:(ESJSONOperationSuccessBlock)success;

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

///----------------------------------
/// @name Getting Default HTTP Values
///----------------------------------

/**
 Returns an `NSSet` object containing the acceptable HTTP content type (http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.17)
 
 By default, this contains `application/json`, `application/x-javascript`, `text/javascript`, `text/x-javascript`, `text/x-json`, `text/json`, and `text/plain`
 */
+ (NSSet *)defaultAcceptableContentTypes;

@end

//
//  ESJSONOperation.h
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
