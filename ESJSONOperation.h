#import "ESHTTPOperation.h"

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
 Creates and returns an `ESJSONOperation` object
 
 @param urlRequest The request object to be loaded asynchronously during execution of the operation
 @param completion ESHTTPOperationCompletionBlock that will be dispatched on completionQueue. Resulting json object can be retrieved from processedResponse.
 
 @see defaultAcceptableStatusCodes
 @see defaultAcceptableContentTypes
 
 @return A new JSON request operation
 */
+ (instancetype)newJSONOperationWithRequest:(NSURLRequest *)urlRequest completion:(ESHTTPOperationCompletionBlock)completion;

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
