//
//	ESJSONOperation.m
//
//	Created by Doug Russell
//	Copyright (c) 2011 Doug Russell. All rights reserved.
//	
//	Licensed under the Apache License, Version 2.0 (the "License");
//	you may not use this file except in compliance with the License.
//	You may obtain a copy of the License at
//	
//	http://www.apache.org/licenses/LICENSE-2.0
//	
//	Unless required by applicable law or agreed to in writing, software
//	distributed under the License is distributed on an "AS IS" BASIS,
//	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//	See the License for the specific language governing permissions and
//	limitations under the License.
//	

#import "ESJSONOperation.h"

@implementation ESJSONOperation

+ (instancetype)newJSONOperationWithRequest:(NSURLRequest *)urlRequest success:(ESJSONOperationSuccessBlock)success
{
	return [self newJSONOperationWithRequest:urlRequest success:success failure:nil];
}

+ (instancetype)newJSONOperationWithRequest:(NSURLRequest *)urlRequest success:(ESJSONOperationSuccessBlock)success failure:(ESJSONOperationFailureBlock)failure
{	 
	ESJSONOperation *op = 
	[[[self class] alloc] initWithRequest:urlRequest 
									 work:^id<NSObject>(ESHTTPOperation *op, NSError *__autoreleasing *error) {
										 if (op.error)
										 {
											 if (error)
												 *error = op.error;
											 return nil;
										 }
										 NSData *data = op.responseBody;
										 if ([data length] == 0) 
										 {
											 return nil;
										 }
										 id json = nil;
										 NSError *jsonError = nil;
										 json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
										 if (jsonError)
										 {
											 if (error)
												 *error = jsonError;
											 return nil;
										 }
										 return json;
									 }
							   completion:^(ESHTTPOperation *op) {
								   ESJSONOperation *jsonOp = (ESJSONOperation *)op;
								   NSError *error = op.error;
								   if (error) 
								   {
									   if (failure) 
									   {
										   failure(jsonOp);
									   }
								   }
								   else
								   {
									   if (success)
									   {
										   success(jsonOp, op.processedResponse);
									   }
								   }
							   }];
	return op;
}

+ (NSSet *)defaultAcceptableContentTypes 
{
	return [NSSet setWithObjects:
			@"application/json", 
			@"application/x-javascript", 
			@"text/javascript", 
			@"text/x-javascript", 
			@"text/x-json", 
			@"text/json", 
			@"text/plain", nil];
}

@end
