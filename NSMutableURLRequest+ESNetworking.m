//
//  NSMutableURLRequest+ESNetworking.h
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

#import "NSMutableURLRequest+ESNetworking.h"

@implementation NSMutableURLRequest (ESNetworking)

+ (NSString *)urlEncodeString:(NSString *)string
{
	NSString *encodedString;
	CFStringRef	escapeChars = CFSTR("/&?=+");
	CFStringRef	encodedText = CFURLCreateStringByAddingPercentEscapes(NULL, 
																	  (__bridge CFStringRef)string, 
																	  NULL, 
																	  escapeChars, 
																	  kCFStringEncodingUTF8);
	encodedString = [NSString stringWithFormat:@"%@", (__bridge NSString *)encodedText];
	CFRelease(encodedText);
	CFRelease(escapeChars);
	return encodedString;
}

+ (NSData *)HTTPBodyWithDictionary:(NSDictionary *)body
{
	NSMutableString *buffer = [NSMutableString string];
	NSArray *keys = [body allKeys];
	NSString *value;
	for (NSString *key in keys) 
	{
		value = [[self class] urlEncodeString:[body objectForKey:key]];
		value = [NSString stringWithFormat:@"&%@=%@", key, value];
		if (value)
			[buffer appendString:value];
	}
	if (buffer.length > 0)
		[buffer deleteCharactersInRange:NSMakeRange(0, 1)];
	NSData *postBody = [NSData dataWithBytes:[buffer UTF8String] length:[buffer length]];
	return postBody;
}

//+ (NSData *)multipartHTTPBodyWithDictionary:(NSDictionary *)body stringBoundary:(NSString *)stringBoundary
//{	
//	NSMutableData *postBody	= [NSMutableData data];
//	NSArray *keys = [body allKeys];
//	NSString *value;
//	for (NSString *key in keys) 
//	{
//		value = [body objectForKey:key];
//		if (value)
//		{
//			[postBody appendData:[[NSString stringWithFormat:@"--%@\r\n", stringBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
//			[postBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", key] dataUsingEncoding:NSUTF8StringEncoding]];
//			[postBody appendData:[[NSString stringWithString:value] dataUsingEncoding:NSUTF8StringEncoding]];
//			[postBody appendData:[[NSString stringWithString:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
//		}
//	}
//	for (NSDictionary *dataDict in bodyDataArray)
//	{
//		NSString	*	fieldName	=	[dataDict objectForKey:@"fieldName"];
//		NSString	*	fileName	=	[dataDict objectForKey:@"fileName"];
//		NSString	*	contentType	=	[dataDict objectForKey:@"contentType"];
//		NSData		*	data		=	[dataDict objectForKey:@"data"];
//		if (fieldName && fileName && contentType && data && !cancelled)
//		{
//			[postBody appendData:[[NSString stringWithFormat:@"--%@\r\n",stringBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
//			[postBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", fieldName, fileName] dataUsingEncoding:NSUTF8StringEncoding]];
//			[postBody appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", contentType] dataUsingEncoding:NSUTF8StringEncoding]];
//			[postBody appendData:data];
//			[postBody appendData:[[NSString stringWithString:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
//		}
//	}
//	[postBody appendData:[[NSString stringWithFormat:@"--%@--\r\n",stringBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
//	
//	return (NSData *)postBody;
//}

+ (instancetype)postRequestWithURL:(NSURL *)url body:(NSDictionary *)body
{
	if (url == nil)
		return nil;
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	[request setHTTPMethod:@"POST"];
	[request setHTTPBody:[[self class] HTTPBodyWithDictionary:body]];
	return request;
}

@end
