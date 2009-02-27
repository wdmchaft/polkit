/*
	This file is part of the PolKit library.
	Copyright (C) 2008-2009 Pierre-Olivier Latour <info@pol-online.net>
	
	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.
	
	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.
	
	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

/*
WebDAV: http://www.ietf.org/rfc/rfc2518.txt and http://msdn.microsoft.com/en-us/library/aa142917(EXCHG.65).aspx
Amazon S3: http://docs.amazonwebservices.com/AmazonS3/2006-03-01/index.html?RESTAPI.html
HTTP Status Codes: http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html
*/

#import <SystemConfiguration/SystemConfiguration.h>

#import "FileTransferController_Internal.h"
#import "NSURL+Parameters.h"
#import "NSData+Encryption.h"
#import "DataStream.h"
#import "Keychain.h"

#define __LOG_HTTP_MESSAGES__ 0

#define kUpdateInterval					0.5
#define kFileBufferSize					(256 * 1024)
#define kDefaultHTTPError				@"Unsupported HTTP response"

#define MAKE_HTTP_ERROR(__STATUS__, ...) MAKE_ERROR(@"http", __STATUS__, __VA_ARGS__)

@interface HTTPTransferController () <DataStreamSource>
+ (BOOL) hasUploadDataStream;
@property(nonatomic, readonly) CFHTTPMessageRef responseHeaders;
@end

@implementation HTTPTransferController

@synthesize SSLCertificateValidationDisabled=_disableSSLCertificates, responseHeaders=_responseHeaders;

+ (NSString*) urlScheme;
{
	return @"http";
}

+ (BOOL) hasAtomicUploads
{
	return YES;
}

+ (BOOL) hasUploadDataStream
{
	return NO;
}

- (void) invalidate
{
	if(_responseHeaders) {
		CFRelease(_responseHeaders);
		_responseHeaders = NULL;
	}
	
	[super invalidate];
}

- (CFHTTPMessageRef) _createHTTPRequestWithMethod:(NSString*)method path:(NSString*)path
{
	NSURL*					url = [self absoluteURLForRemotePath:path];
	NSString*				user = [[self baseURL] user];
	NSString*				password = [[self baseURL] passwordByReplacingPercentEscapes];
	CFHTTPMessageRef		message;
	
	message = CFHTTPMessageCreateRequest(kCFAllocatorDefault, (CFStringRef)method, (CFURLRef)url, kCFHTTPVersion1_1);
	if(message == NULL)
	return NULL;
	
	if(user && password) {
		if(!CFHTTPMessageAddAuthentication(message, NULL, (CFStringRef)user, (CFStringRef)password, kCFHTTPAuthenticationSchemeBasic, false)) {
			CFRelease(message);
			return NULL;
		}
	}
	
	CFHTTPMessageSetHeaderFieldValue(message, CFSTR("User-Agent"), (CFStringRef)NSStringFromClass([self class]));
	CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Connection"), CFSTR("close"));
	
	return message;
}

- (CFReadStreamRef) _createReadStreamWithHTTPRequest:(CFHTTPMessageRef)request bodyStream:(NSInputStream*)stream
{
	CFReadStreamRef			readStream = NULL;
	CFDictionaryRef			proxySettings;
	CFMutableDictionaryRef	sslSettings;
	
#if __LOG_HTTP_MESSAGES__
	NSLog(@"%@ [HTTP Request]\n%@", self, [[[NSString alloc] initWithData:[(id)CFHTTPMessageCopySerializedMessage(request) autorelease] encoding:NSUTF8StringEncoding] autorelease]);
#endif
	
	if(stream)
	readStream = CFReadStreamCreateForStreamedHTTPRequest(kCFAllocatorDefault, request, (CFReadStreamRef)stream);
	else
	readStream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, request);
	
	if([[[self class] urlScheme] isEqualToString:@"https"] && _disableSSLCertificates) {
		sslSettings = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFDictionarySetValue(sslSettings, kCFStreamSSLValidatesCertificateChain, kCFBooleanFalse);
		CFReadStreamSetProperty(readStream, kCFStreamPropertySSLSettings, sslSettings);
		CFRelease(sslSettings);
	}
	
	if((proxySettings = SCDynamicStoreCopyProxies(NULL))) {
		CFReadStreamSetProperty(readStream, kCFStreamPropertyHTTPProxy, (proxySettings));
		CFRelease(proxySettings);
	}
	
	CFReadStreamSetProperty(readStream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue);
	
	//kCFStreamSSLCertificates
	//kCFStreamPropertyHTTPAttemptPersistentConnection
	
	return readStream;
}

- (void) readStreamClientCallBack:(CFReadStreamRef)stream type:(CFStreamEventType)type
{
	CFStringRef					value;
	
	switch(type) {
		
		case kCFStreamEventHasBytesAvailable:
		if((_responseHeaders == NULL) && (_responseHeaders = (CFHTTPMessageRef)CFReadStreamCopyProperty(stream, kCFStreamPropertyHTTPResponseHeader))) {
			value = CFHTTPMessageCopyHeaderFieldValue(_responseHeaders, CFSTR("Content-Length"));
			if(value) {
				[self setMaxLength:[(NSString*)value integerValue]];
				CFRelease(value);
			}
		}
		break;
		
		case kCFStreamEventEndEncountered:
		if(_responseHeaders == NULL)
		_responseHeaders = (CFHTTPMessageRef)CFReadStreamCopyProperty(stream, kCFStreamPropertyHTTPResponseHeader);
		break;
		
	}
	
	[super readStreamClientCallBack:stream type:type];
}

- (id) processReadResultStream:(NSOutputStream*)stream userInfo:(id)info error:(NSError**)error
{
	NSInteger				status = (_responseHeaders ? CFHTTPMessageGetResponseStatusCode(_responseHeaders) : -1);
	NSString*				method = info;
	id						result = nil;
	
	if(error)
	*error = nil;
	
#if __LOG_HTTP_MESSAGES__
	if([self isMemberOfClass:[HTTPTransferController class]])
	NSLog(@"%@ [HTTP Response]\n%@\n%@", self, [(id)(_responseHeaders ? CFHTTPMessageCopyResponseStatusLine(_responseHeaders) : NULL) autorelease], [(id)(_responseHeaders ? CFHTTPMessageCopyAllHeaderFields(_responseHeaders) : NULL) autorelease]);
#endif
	
	if([method isEqualToString:@"GET"]) {
		if(status == 200)
		result = [NSNumber numberWithBool:YES];
	}
	else if([method isEqualToString:@"PUT"]) {
		if((status == 200) || (status == 201) || (status == 204))
		result = [NSNumber numberWithBool:YES];
	}
	
	if((result == nil) && error && (*error == nil))
	*error = MAKE_HTTP_ERROR(status, kDefaultHTTPError);
	
	return result;
}

- (BOOL) _downloadFileFromPath:(NSString*)remotePath toStream:(NSOutputStream*)stream
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			readStream;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	request = [self _createHTTPRequestWithMethod:@"GET" path:remotePath];
	if(request == NULL)
	return NO;
	
	readStream = [self _createReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [[self runReadStream:readStream dataStream:stream userInfo:@"GET" isFileTransfer:YES] boolValue];
}

- (BOOL) openDataStream:(id)userInfo
{
	return ([userInfo isKindOfClass:[NSInputStream class]] ? [self openInputStream:userInfo isFileTransfer:YES] : [(id<DataStreamSource>)super openDataStream:userInfo]);
}

- (NSInteger) readDataFromStream:(id)userInfo buffer:(void*)buffer maxLength:(NSUInteger)length
{
	NSInteger				numBytes;
	
	if(![userInfo isKindOfClass:[NSInputStream class]])
	return [(id<DataStreamSource>)super readDataFromStream:userInfo buffer:buffer maxLength:length];
	
	numBytes = [self readFromInputStream:userInfo bytes:buffer maxLength:length];
	if(numBytes > 0)
	[self setCurrentLength:([self currentLength] + numBytes)]; //FIXME: We could also use kCFStreamPropertyHTTPRequestBytesWrittenCount
	
	return numBytes;	
}

- (void) closeDataStream:(id)userInfo
{
	if([userInfo isKindOfClass:[NSInputStream class]])
	[self closeInputStream:userInfo];
	else
	[(id<DataStreamSource>)super closeDataStream:userInfo];
}

- (BOOL) _uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream
{
	NSString*				type = nil;
	BOOL					success = NO;
	NSString*				filePath = nil;
	NSString*				UTI;
	CFHTTPMessageRef		request;
	CFReadStreamRef			readStream;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	//HACK: Force CFReadStreamCreateForStreamedHTTPRequest() to go through our stream methods by using a DataStream wrapper
	stream = [[[DataReadStream alloc] initWithDataSource:self userInfo:stream] autorelease];
	if(stream == nil)
	return NO;
	
	request = [self _createHTTPRequestWithMethod:@"PUT" path:remotePath];
	if(request == NULL)
	return NO;
	
	if([[remotePath pathExtension] length]) {
		UTI = [(NSString*)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)[remotePath pathExtension], NULL) autorelease];
		if([UTI length])
		type = [(NSString *)UTTypeCopyPreferredTagWithClass((CFStringRef)UTI, kUTTagClassMIMEType) autorelease];
	}
	if(![type length])
	type = @"application/octet-stream";
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Content-Type"), (CFStringRef)type);
	
	if([self maxLength] > 0)
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Content-Length"), (CFStringRef)[NSString stringWithFormat:@"%i", [self maxLength]]);
	
	readStream = [self _createReadStreamWithHTTPRequest:request bodyStream:stream];
	CFRelease(request);
	
	success = [[self runReadStream:readStream dataStream:([[self class] hasUploadDataStream] ? [NSOutputStream outputStreamToMemory] : nil) userInfo:@"PUT" isFileTransfer:YES] boolValue];
	
	if(filePath)
	[[NSFileManager defaultManager] removeItemAtPath:filePath error:NULL];
	
	return success;
}

@end

@implementation SecureHTTPTransferController

+ (NSString*) urlScheme;
{
	return @"https";
}

@end

@implementation WebDAVTransferController

static NSDictionary* _DictionaryFromDAVProperties(NSXMLElement* element, NSString** path)
{
	NSMutableDictionary*	dictionary = [NSMutableDictionary dictionary];
	NSArray*				array;
	
	*path = [[[[[element elementsForName:@"D:href"] objectAtIndex:0] stringValue] lastPathComponent] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
	
	element = [[element elementsForName:@"D:propstat"] objectAtIndex:0];
	element = [[element elementsForName:@"D:prop"] objectAtIndex:0];
	
	array = [element elementsForName:@"D:resourcetype"];
	if([array count]) {
		if([[[array objectAtIndex:0] elementsForName:@"D:collection"] count])
		[dictionary setObject:NSFileTypeDirectory forKey:NSFileType];
		else
		[dictionary setObject:NSFileTypeRegular forKey:NSFileType];
	}
	
	array = [element elementsForName:@"D:creationdate"];
	if([array count])
	[dictionary setValue:[NSCalendarDate dateWithString:[[array objectAtIndex:0] stringValue] calendarFormat:@"%Y-%m-%dT%H:%M:%SZ"] forKey:NSFileCreationDate]; //FIXME: We ignore Z and assume UTC (%z)
	array = [element elementsForName:@"D:modificationdate"];
	if([array count])
	[dictionary setValue:[NSCalendarDate dateWithString:[[array objectAtIndex:0] stringValue] calendarFormat:@"%Y-%m-%dT%H:%M:%SZ"] forKey:NSFileModificationDate]; //FIXME: We ignore Z and assume UTC (%z)
	else {
		array = [element elementsForName:@"D:getlastmodified"];
		if([array count])
		[dictionary setValue:[NSCalendarDate dateWithString:[[array objectAtIndex:0] stringValue] calendarFormat:@"%a, %d %b %Y %H:%M:%S %Z"] forKey:NSFileModificationDate];
	}
	array = [element elementsForName:@"D:getcontentlength"];
	if([array count])
	[dictionary setValue:[NSNumber numberWithInteger:[[[array objectAtIndex:0] stringValue] integerValue]] forKey:NSFileSize];
	
	return dictionary;
}	

- (id) processReadResultStream:(NSOutputStream*)stream userInfo:(id)info error:(NSError**)error
{
	NSData*					data = [stream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
	CFHTTPMessageRef		responseHeaders = [self responseHeaders];
	NSInteger				status = (responseHeaders ? CFHTTPMessageGetResponseStatusCode(responseHeaders) : -1);
	NSString*				method = info;
	NSStringEncoding		encoding = NSUTF8StringEncoding;
	id						result = nil;
	id						body = nil;
	NSString*				mime = nil;
	NSString*				type;
	NSRange					range;
	NSArray*				elements;
	NSXMLElement*			element;
	NSDictionary*			properties;
	NSString*				path;
	
	if(error)
	*error = nil;
	
#if __LOG_HTTP_MESSAGES__
	NSLog(@"%@ [HTTP Response]\n%@\n%@", self, [(id)(responseHeaders ? CFHTTPMessageCopyResponseStatusLine(responseHeaders) : NULL) autorelease], [(id)(responseHeaders ? CFHTTPMessageCopyAllHeaderFields(responseHeaders) : NULL) autorelease]);
#endif
	
	if(responseHeaders && [data length]) {
		type = [[(NSString*)CFHTTPMessageCopyHeaderFieldValue(responseHeaders, CFSTR("Content-Type")) autorelease] lowercaseString];
		if([type length]) {
			range = [type rangeOfString:@";" options:0 range:NSMakeRange(0, [type length])];
			if(range.location != NSNotFound)
			mime = [type substringToIndex:range.location];
			else
			mime = type;
			
			range = [type rangeOfString:@"charset=" options:0 range:NSMakeRange(0, [type length])];
			if(range.location != NSNotFound) {
				type = [type substringFromIndex:(range.location + range.length)];
				range = [type rangeOfString:@";" options:0 range:NSMakeRange(0, [type length])]; //FIXME: Should we trim spaces?
				if(range.location != NSNotFound)
				type = [type substringToIndex:range.location];
				if([type hasPrefix:@"\""] && [type hasSuffix:@"\""])
				type = [type substringWithRange:NSMakeRange(1, [type length] - 2)];
				encoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)type);
				if(encoding != kCFStringEncodingInvalidId)
				encoding = CFStringConvertEncodingToNSStringEncoding(encoding);
				else {
					NSLog(@"%s: Invalid charset value \"%@\"", __FUNCTION__, type);
					encoding = NSUTF8StringEncoding;
				}
			}
		}
		
		if([mime isEqualToString:@"text/plain"])
		body = [[NSString alloc] initWithData:data encoding:encoding];
		else if([mime isEqualToString:@"text/xml"] || [mime isEqualToString:@"application/xml"])
		body = [[NSXMLDocument alloc] initWithData:data options:NSXMLNodeOptionsNone error:error];
		else if([mime length]) {
			if(error)
			*error = MAKE_FILETRANSFERCONTROLLER_ERROR(@"Unsupported MIME type \"%@\"", mime);
		}
	}
	
	if([method isEqualToString:@"PROPFIND"]) {
		if((status == 207) && [body isKindOfClass:[NSXMLDocument class]]) {
			elements = [[(NSXMLDocument*)body rootElement] elementsForName:@"D:response"];
			result = [NSMutableDictionary dictionary];
			for(element in elements) {
				if(element == [elements objectAtIndex:0])
				continue;
				properties = _DictionaryFromDAVProperties(element, &path);
				[result setObject:properties forKey:path];
			}
		}
	}
	else if([method isEqualToString:@"MOVE"] || [method isEqualToString:@"COPY"]) {
		if((status == 201) || (status == 204))
		result = [NSNumber numberWithBool:YES];
	}
	else if([method isEqualToString:@"DELETE"]) {
		if((status == 204) || (status == 404))
		result = [NSNumber numberWithBool:YES];
	}
	else if([method isEqualToString:@"MKCOL"]) {
		if(status == 201)
		result = [NSNumber numberWithBool:YES];
	}
	else
	result = [super processReadResultStream:stream userInfo:info error:error];
	
	[body release];
	
	if((result == nil) && error && (*error == nil))
	*error = MAKE_HTTP_ERROR(status, kDefaultHTTPError);
	
	return result;
}

- (NSDictionary*) contentsOfDirectoryAtPath:(NSString*)remotePath
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	
	if(![remotePath length])
	remotePath = @"/";
	else if(![remotePath hasSuffix:@"/"])
	remotePath = [remotePath stringByAppendingString:@"/"];
	
	request = [self _createHTTPRequestWithMethod:@"PROPFIND" path:remotePath];
	if(request == NULL)
	return nil;
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Depth"), CFSTR("1"));
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Brief"), CFSTR("T"));
	
	stream = [self _createReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [self runReadStream:stream dataStream:[NSOutputStream outputStreamToMemory] userInfo:@"PROPFIND" isFileTransfer:NO];
}

- (BOOL) createDirectoryAtPath:(NSString*)remotePath
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	
	request = [self _createHTTPRequestWithMethod:@"MKCOL" path:remotePath];
	if(request == NULL)
	return NO;
	
	stream = [self _createReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [[self runReadStream:stream dataStream:nil userInfo:@"MKCOL" isFileTransfer:NO] boolValue];
}

- (BOOL) _movePath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath copy:(BOOL)copy
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	
	request = [self _createHTTPRequestWithMethod:(copy ? @"COPY" : @"MOVE") path:fromRemotePath];
	if(request == NULL)
	return NO;
#if 0
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Destination"), (CFStringRef)[[[self baseURL] path] stringByAppendingPathComponent:[toRemotePath stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]);
#else
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Destination"), (CFStringRef)[[self absoluteURLForRemotePath:toRemotePath] absoluteString]);
#endif
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Overwrite"), CFSTR("T"));
	
	stream = [self _createReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [[self runReadStream:stream dataStream:nil userInfo:(copy ? @"COPY" : @"MOVE") isFileTransfer:NO] boolValue];
}

- (BOOL) movePath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath
{
	return [self _movePath:fromRemotePath toPath:toRemotePath copy:NO];
}

- (BOOL) copyPath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath
{
	return [self _movePath:fromRemotePath toPath:toRemotePath copy:YES];
}

- (BOOL) _deletePath:(NSString*)remotePath
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	
	request = [self _createHTTPRequestWithMethod:@"DELETE" path:remotePath];
	if(request == NULL)
	return NO;
	
	stream = [self _createReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [[self runReadStream:stream dataStream:nil userInfo:@"DELETE" isFileTransfer:NO] boolValue];
}

- (BOOL) deleteFileAtPath:(NSString*)remotePath
{
	return [self _deletePath:remotePath];
}

- (BOOL) deleteDirectoryRecursivelyAtPath:(NSString*)remotePath
{
	//NOTE: Some servers require the trailing slash, while some others don't
	if(![remotePath hasSuffix:@"/"])
	remotePath = [remotePath stringByAppendingString:@"/"];
	
	return [self _deletePath:remotePath];
}

@end

@implementation WebDAVTransferController (iDisk)

- (id) initWithIDiskForLocalUser:(NSString*)basePath
{
	return [self initWithIDiskForUser:nil basePath:basePath];
}

- (id) initWithIDiskForUser:(NSString*)username basePath:(NSString*)basePath
{
	return [self initWithIDiskForUser:username password:nil basePath:basePath];
}

- (id) initWithIDiskForUser:(NSString*)username password:(NSString*)password basePath:(NSString*)basePath
{
	if(username == nil)
	username = [[NSUserDefaults standardUserDefaults] stringForKey:@"iToolsMember"];
	
	if([username length] && (password == nil))
	password = [[Keychain sharedKeychain] genericPasswordForService:@"iTools" account:username];
	
	if([username length] && ![username isEqualToString:@"public"] && ![basePath hasSuffix:[NSString stringWithFormat:@"/%@", username]] && ![basePath hasPrefix:[NSString stringWithFormat:@"/%@/", username]])
	basePath = [[NSString stringWithFormat:@"/%@", username] stringByAppendingPathComponent:basePath];
	
	return [self initWithHost:kFileTransferHost_iDisk port:0 username:username password:password basePath:basePath];
}

@end

@implementation SecureWebDAVTransferController

+ (NSString*) urlScheme;
{
	return @"https";
}

- (id) initWithIDiskForUser:(NSString*)username password:(NSString*)password basePath:(NSString*)basePath
{
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

@end

@implementation AmazonS3TransferController

@synthesize productToken=_productToken, userToken=_userToken;

+ (NSDictionary*) activateDesktopProduct:(NSString*)productToken activationKey:(NSString*)activationKey expirationInterval:(NSTimeInterval)expirationInterval error:(NSError**)error
{
	NSOutputStream*				stream = [NSOutputStream outputStreamToMemory];
	NSMutableDictionary*		dictionary = nil;
	NSString*					string;
	HTTPTransferController*		transferController;
	NSData*						data;
	NSXMLDocument*				document;
	BOOL						success;
	NSURL*						url;
	NSArray*					elements;
	NSXMLElement*				element;
	
	if(error)
	*error = nil;
	
	if(![productToken length] || ![activationKey length])
	return nil;
	
	string = [NSString stringWithFormat:@"https://ls.amazonaws.com/?Action=ActivateDesktopProduct&ActivationKey=%@&ProductToken=%@%@&Version=2008-04-28", activationKey, productToken, (expirationInterval > 0.0 ? [NSString stringWithFormat:@"&TokenExpiration=PT%.0fS", expirationInterval] : @"")]; //NOTE: http://en.wikipedia.org/wiki/ISO_8601#Durations
	url = [NSURL URLWithString:[string stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
	transferController = [[SecureHTTPTransferController alloc] initWithURL:url];
	success = [transferController downloadFileFromPath:nil toStream:stream];
	[transferController release];
	
	data = [stream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
	if([data length]) {
		document = [[NSXMLDocument alloc] initWithData:data options:NSXMLNodeOptionsNone error:error];
		if(document) {
			if(success && (elements = [[document rootElement] elementsForName:@"ActivateDesktopProductResult"])) {
				if([elements count]) {
					element = [elements objectAtIndex:0];
					dictionary = [NSMutableDictionary dictionary];
					elements = [element elementsForName:@"UserToken"];
					string = ([elements count] ? [(NSXMLElement*)[elements objectAtIndex:0] stringValue] : nil);
					[dictionary setValue:string forKey:kAmazonS3ActivationInfo_UserToken];
					elements = [element elementsForName:@"AWSAccessKeyId"];
					string = ([elements count] ? [(NSXMLElement*)[elements objectAtIndex:0] stringValue] : nil);
					[dictionary setValue:string forKey:kAmazonS3ActivationInfo_AccessKeyID];
					elements = [element elementsForName:@"SecretAccessKey"];
					string = ([elements count] ? [(NSXMLElement*)[elements objectAtIndex:0] stringValue] : nil);
					[dictionary setValue:string forKey:kAmazonS3ActivationInfo_SecretAccessKey];
				}
				if([dictionary count] != 3) {
					if(error)
					*error = MAKE_ERROR(@"s3", -1, (string ? string : @"Incomplete response"));
					dictionary = nil;
				}
			}
			else if(error) {
				string = nil;
				elements = [[document rootElement] elementsForName:@"Error"];
				if([elements count]) {
					element = [elements objectAtIndex:0];
					elements = [element elementsForName:@"Message"];
					string = ([elements count] ? [(NSXMLElement*)[elements objectAtIndex:0] stringValue] : nil);
					if(string == nil) {
						elements = [element elementsForName:@"Code"];
						string = ([elements count] ? [(NSXMLElement*)[elements objectAtIndex:0] stringValue] : nil);
					}
				}
				*error = MAKE_ERROR(@"s3", -1, (string ? string : @"Invalid response"));
			}
			[document release];
		}
	}
	else if(error)
	*error = MAKE_ERROR(@"s3", -1, @"Failed retrieving activation data");

	return dictionary;
}

+ (BOOL) hasUploadDataStream
{
	return YES;
}

- (id) initWithURL:(NSURL*)url
{
	if(![[url host] hasSuffix:kFileTransferHost_AmazonS3] || [url port] || ![url user] || ![url passwordByReplacingPercentEscapes] || [[url path] length]) {
		[self release];
		return nil;
	}
	
	return [super initWithURL:url];
}

- (id) initWithAccessKeyID:(NSString*)accessKeyID secretAccessKey:(NSString*)secretAccessKey bucket:(NSString*)bucket
{
	if(![accessKeyID length] || ![secretAccessKey length]) {
		[self release];
		return nil;
	}
	
	return [self initWithURL:[NSURL URLWithScheme:[[self class] urlScheme] user:accessKeyID password:secretAccessKey host:([bucket length] ? [NSString stringWithFormat:@"%@.%@", bucket, kFileTransferHost_AmazonS3] : kFileTransferHost_AmazonS3) port:0 path:nil]];
}

- (void) dealloc
{
	[_userToken release];
	[_productToken release];
	
	[super dealloc];
}

/* Override behavior */
- (NSURL*) absoluteURLForRemotePath:(NSString*)path
{
	if(path && ![path length])
	path = @"/";
	
	return [super absoluteURLForRemotePath:path];
}

- (NSString*) bucket
{
	NSString*				host = [[self baseURL] host];
	NSRange					range;
	
	range = [host rangeOfString:[@"." stringByAppendingString:kFileTransferHost_AmazonS3]];
	if(range.location != NSNotFound)
	return [host substringToIndex:range.location];
	
	return nil;
}

/* See http://docs.amazonwebservices.com/AmazonS3/2006-03-01/index.html?RESTAuthentication.html */
- (CFReadStreamRef) _createReadStreamWithHTTPRequest:(CFHTTPMessageRef)request bodyStream:(id)stream
{
	NSURL*					url = [(id)CFHTTPMessageCopyRequestURL(request) autorelease];
	NSString*				bucket = [self bucket];
	NSMutableString*		amzHeaders = [NSMutableString string];
	NSMutableString*		buffer;
	NSString*				authorization;
	NSCalendarDate*			date;
	NSString*				dateString;
	NSDictionary*			headers;
	NSString*				header;
	
	date = [NSCalendarDate calendarDate];
	[date setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	dateString = [date descriptionWithCalendarFormat:@"%a, %d %b %Y %H:%M:%S %z"];
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Date"), (CFStringRef)dateString);
	
	if(_productToken && _userToken)
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("x-amz-security-token"), (CFStringRef)[NSString stringWithFormat:@"%@,%@", _productToken, _userToken]);
	
	headers = [(id)CFHTTPMessageCopyAllHeaderFields(request) autorelease];
	buffer = [NSMutableString new];
	[buffer appendFormat:@"%@\n", [(id)CFHTTPMessageCopyRequestMethod(request) autorelease]];
	[buffer appendFormat:@"%@\n", ([headers objectForKey:@"Content-MD5"] ? [headers objectForKey:@"Content-MD5"] : @"")];
	[buffer appendFormat:@"%@\n", ([headers objectForKey:@"Content-Type"] ? [headers objectForKey:@"Content-Type"] : @"")];
	[buffer appendFormat:@"%@\n", dateString];
	for(header in [[headers allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		if([header hasPrefix:@"X-Amz-"])
		[amzHeaders appendFormat:@"%@:%@\n", [header lowercaseString], [headers objectForKey:header]];
	}
	[buffer appendString:amzHeaders];
	[buffer appendFormat:@"%@%@", (bucket ? [@"/" stringByAppendingString:bucket] : @""), [[url path] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
	authorization = [[[buffer dataUsingEncoding:NSUTF8StringEncoding] sha1HMacWithKey:[[self baseURL] passwordByReplacingPercentEscapes]] encodeBase64];
	[buffer release];
	
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Authorization"), (CFStringRef)[NSString stringWithFormat:@"AWS %@:%@", [[self baseURL] user], authorization]);
	
	return [super _createReadStreamWithHTTPRequest:request bodyStream:stream];
}

static NSDictionary* _DictionaryFromS3Buckets(NSXMLElement* element, NSString** path)
{
	NSMutableDictionary*	dictionary = [NSMutableDictionary dictionary];
	NSArray*				array;
	
	*path = [[[element elementsForName:@"Name"] objectAtIndex:0] stringValue];
	
	[dictionary setObject:NSFileTypeDirectory forKey:NSFileType];
	array = [element elementsForName:@"CreationDate"];
	if([array count])
	[dictionary setValue:[NSCalendarDate dateWithString:[[array objectAtIndex:0] stringValue] calendarFormat:@"%Y-%m-%dT%H:%M:%S.%FZ"] forKey:NSFileCreationDate]; //FIXME: We ignore Z and assume UTC (%z)
	
	return dictionary;
}	

static NSDictionary* _DictionaryFromS3Objects(NSXMLElement* element, NSString* basePath, NSString** path)
{
	NSMutableDictionary*	dictionary = [NSMutableDictionary dictionary];
	BOOL					isDirectory = NO;
	NSArray*				array;
	NSString*				fullPath;
	NSRange					range;
	
	fullPath = [[[element elementsForName:@"Key"] objectAtIndex:0] stringValue];
	if(basePath) {
		range = [fullPath rangeOfString:@"/" options:0 range:NSMakeRange([basePath length] + 1, [fullPath length] - [basePath length] - 1)];
		if((range.location != NSNotFound) && (range.location != [fullPath length] - 1))
		return nil;
		
		if([fullPath characterAtIndex:([fullPath length] - 1)] == '/')
		isDirectory = YES;
		
		*path = [fullPath lastPathComponent];
		if(isDirectory && [*path isEqualToString:basePath])
		return nil;
		
		[dictionary setObject:(isDirectory ? NSFileTypeDirectory : NSFileTypeRegular) forKey:NSFileType];
	}
	else
	*path = fullPath;
	
	array = [element elementsForName:@"LastModified"];
	if([array count])
	[dictionary setValue:[NSCalendarDate dateWithString:[[array objectAtIndex:0] stringValue] calendarFormat:@"%Y-%m-%dT%H:%M:%S.%FZ"] forKey:NSFileModificationDate]; //FIXME: We ignore Z and assume UTC (%z)
	if(isDirectory == NO) {
		array = [element elementsForName:@"Size"];
		if([array count])
		[dictionary setValue:[NSNumber numberWithInteger:[[[array objectAtIndex:0] stringValue] integerValue]] forKey:NSFileSize];
	}
	
	return dictionary;
}	

- (id) processReadResultStream:(NSOutputStream*)stream userInfo:(id)info error:(NSError**)error
{
	NSData*					data = [stream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
	CFHTTPMessageRef		responseHeaders = [self responseHeaders];
	NSInteger				status = (responseHeaders ? CFHTTPMessageGetResponseStatusCode(responseHeaders) : -1);
	NSString*				method = info;
	id						result = nil;
	id						body = nil;
	NSString*				mime = nil;
	NSString*				type;
	NSRange					range;
	NSArray*				elements;
	NSXMLElement*			element;
	NSDictionary*			properties;
	NSString*				path;
	NSString*				string;
	
	if(error)
	*error = nil;
	
#if __LOG_HTTP_MESSAGES__
	NSLog(@"%@ [HTTP Response]\n%@\n%@", self, [(id)(responseHeaders ? CFHTTPMessageCopyResponseStatusLine(responseHeaders) : NULL) autorelease], [(id)(responseHeaders ? CFHTTPMessageCopyAllHeaderFields(responseHeaders) : NULL) autorelease]);
#endif
	
	if(responseHeaders && [data length]) {
		type = [[(NSString*)CFHTTPMessageCopyHeaderFieldValue(responseHeaders, CFSTR("Content-Type")) autorelease] lowercaseString];
		if([type length]) {
			range = [type rangeOfString:@";" options:0 range:NSMakeRange(0, [type length])];
			if(range.location != NSNotFound)
			mime = [type substringToIndex:range.location];
			else
			mime = type;
		}
		
		if([mime isEqualToString:@"application/xml"])
		body = [[NSXMLDocument alloc] initWithData:data options:NSXMLNodeOptionsNone error:error];
		else if([mime length]) {
			if(error)
			*error = MAKE_FILETRANSFERCONTROLLER_ERROR(@"Unsupported MIME type \"%@\"", mime);
		}
	}
	
	if([method hasPrefix:@"GET:"]) {
		if((status == 200) && [body isKindOfClass:[NSXMLDocument class]]) {
			if([self bucket]) {
				type = [method substringFromIndex:4];
				if([type isEqualToString:kAmazonS3TransferControllerAllKeysPath])
				type = nil;
				
				elements = [[(NSXMLDocument*)body rootElement] elementsForName:@"Contents"];
				result = [NSMutableDictionary dictionary];
				for(element in elements) {
					properties = _DictionaryFromS3Objects(element, type, &path);
					if(properties)
					[result setObject:properties forKey:path];
				}
			}
			else {
				elements = [[(NSXMLDocument*)body rootElement] elementsForName:@"Buckets"];
				elements = [(NSXMLElement*)[elements objectAtIndex:0] elementsForName:@"Bucket"];
				result = [NSMutableDictionary dictionary];
				for(element in elements) {
					properties = _DictionaryFromS3Buckets(element, &path);
					if(properties)
					[result setObject:properties forKey:path];
				}
			}
		}
	}
	else if([method isEqualToString:@"DELETE"]) {
		if(status == 204)
		result = [NSNumber numberWithBool:YES];
	}
	else if([method isEqualToString:@"COPY"]) {
		if((status == 200) && [body isKindOfClass:[NSXMLDocument class]] && [[[body rootElement] name] isEqualToString:@"CopyObjectResult"])
		result = [NSNumber numberWithBool:YES];
	}
	else
	result = [super processReadResultStream:stream userInfo:info error:error];
	
	if((result == nil) && error && ((*error == nil) || [[*error localizedDescription] isEqualToString:kDefaultHTTPError])) {
		if([body isKindOfClass:[NSXMLDocument class]]) {
			elements = [[(NSXMLDocument*)body rootElement] elementsForName:@"Message"];
			string = ([elements count] ? [(NSXMLElement*)[elements objectAtIndex:0] stringValue] : nil);
			if(string == nil) {
				elements = [[(NSXMLDocument*)body rootElement] elementsForName:@"Code"];
				string = ([elements count] ? [(NSXMLElement*)[elements objectAtIndex:0] stringValue] : nil);
			}
		}
		else
		string = nil;
		if(string)
		*error = MAKE_HTTP_ERROR(status, @"Amazon S3 Error: %@", string);
		else
		*error = MAKE_HTTP_ERROR(status, kDefaultHTTPError);
	}
	
	[body release];
	
	return result;
}

- (NSDictionary*) contentsOfDirectoryAtPath:(NSString*)remotePath
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	
	if([remotePath length] && ![remotePath isEqualToString:kAmazonS3TransferControllerAllKeysPath])
	return nil;
	
	//FIXME: Amazon S3 doesn't support directories although you can emulate paths using "/" in keys
	request = [self _createHTTPRequestWithMethod:@"GET" path:([remotePath length] && ![remotePath isEqualToString:kAmazonS3TransferControllerAllKeysPath] ? [NSString stringWithFormat:@"?prefix=%@/", remotePath] : @"")];
	if(request == NULL)
	return nil;
	
	stream = [self _createReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [self runReadStream:stream dataStream:[NSOutputStream outputStreamToMemory] userInfo:[NSString stringWithFormat:@"GET:%@", (remotePath ? remotePath : @"")] isFileTransfer:NO];
}

- (BOOL) _deletePath:(NSString*)remotePath
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	
	request = [self _createHTTPRequestWithMethod:@"DELETE" path:remotePath];
	if(request == NULL)
	return NO;
	
	stream = [self _createReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [[self runReadStream:stream dataStream:nil userInfo:@"DELETE" isFileTransfer:NO] boolValue];
}

- (BOOL) deleteFileAtPath:(NSString*)remotePath
{
	return [self _deletePath:remotePath];
}

- (BOOL) copyPath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	
	request = [self _createHTTPRequestWithMethod:@"PUT" path:toRemotePath];
	if(request == NULL)
	return NO;
	
	fromRemotePath = [(id)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)fromRemotePath, NULL, NULL, kCFStringEncodingUTF8) autorelease];
	CFHTTPMessageSetHeaderFieldValue(request, CFSTR("x-amz-copy-source"), (CFStringRef)[NSString stringWithFormat:@"/%@/%@", [self bucket], fromRemotePath]);
	
	stream = [self _createReadStreamWithHTTPRequest:request bodyStream:nil];
	CFRelease(request);
	
	return [[self runReadStream:stream dataStream:[NSOutputStream outputStreamToMemory] userInfo:@"COPY" isFileTransfer:NO] boolValue];
}

- (NSDictionary*) allBuckets
{
	if([self bucket])
	return nil;
	
	return [self contentsOfDirectoryAtPath:nil];
}

- (BOOL) createBucket
{
	return [self createBucketAtLocation:nil];
}

- (BOOL) createBucketAtLocation:(NSString*)location
{
	CFHTTPMessageRef		request;
	CFReadStreamRef			stream;
	NSInputStream*			bodyStream;
	NSString*				xmlString;
	
	request = [self _createHTTPRequestWithMethod:@"PUT" path:@""];
	if(request == NULL)
	return NO;
	
	if([location length]) {
		xmlString = [NSString stringWithFormat:@"<CreateBucketConfiguration>\n\t<LocationConstraint>%@</LocationConstraint>\n</CreateBucketConfiguration>\n", location];
		bodyStream = [NSInputStream inputStreamWithData:[xmlString dataUsingEncoding:NSUTF8StringEncoding]];
	}
	else
	bodyStream = nil;
	
	stream = [self _createReadStreamWithHTTPRequest:request bodyStream:bodyStream];
	CFRelease(request);
	
	return [[self runReadStream:stream dataStream:nil userInfo:@"PUT" isFileTransfer:NO] boolValue];
}

- (BOOL) deleteBucket
{
	return [self _deletePath:@""];
}

@end

@implementation SecureAmazonS3TransferController

+ (NSString*) urlScheme;
{
	return @"https";
}

@end
