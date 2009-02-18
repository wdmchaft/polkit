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

#import <SystemConfiguration/SystemConfiguration.h>
#import <curl/curl.h>

#import "FileTransferController_Internal.h"
#import "NSURL+Parameters.h"

#define __USE_COMMAND_PROGRESS__ 0
#define __USE_LISTING_PROGRESS__ 0

static inline NSError* _MakeCURLError(CURLcode code, const char* message)
{
	return [NSError errorWithDomain:@"curl" code:code userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithUTF8String:message], NSLocalizedDescriptionKey, nil]];
}

static void _ResetCURLHandle(CURL* handle)
{
	CFDictionaryRef			proxySettings;
	const char*				host;
	long					port;
	//NSArray*				array;
	
	curl_easy_reset(handle);
	//curl_easy_setopt(handle, CURLOPT_VERBOSE, (long)1);
	
	if((proxySettings = SCDynamicStoreCopyProxies(NULL))) {
		if([[(NSDictionary*)proxySettings objectForKey:(id)kSCPropNetProxiesFTPEnable] boolValue]) {
			if((host = [[(NSDictionary*)proxySettings objectForKey:(id)kSCPropNetProxiesFTPProxy] UTF8String]))
			curl_easy_setopt(handle, CURLOPT_PROXY, host);
			if((port = [[(NSDictionary*)proxySettings objectForKey:(id)kSCPropNetProxiesFTPPort] longValue]))
			curl_easy_setopt(handle, CURLOPT_PROXYPORT, port);
			/*
			if((array = [(NSDictionary*)proxySettings objectForKey:(id)kSCPropNetProxiesExceptionsList])) 
			curl_easy_setopt(handle, CURLOPT_NOPROXY, [[array componentsJoinedByString:@","] UTF8String]);
			*/
		}
		CFRelease(proxySettings);
	}
}

@implementation FTPTransferController

+ (void) initialize
{
	if(self == [FTPTransferController class])
	curl_global_init(CURL_GLOBAL_DEFAULT);
}

+ (NSString*) urlScheme;
{
	return @"ftp";
}

- (id) initWithURL:(NSURL*)url
{
	if((self = [super initWithURL:url])) {
		_handle = curl_easy_init();
		if(_handle == NULL) {
			NSLog(@"%s: curl_easy_init() failed", __FUNCTION__);
			[self release];
			return nil;
		}
	}
	
	return self;
}

- (void) invalidate
{
	if(_handle) {
		curl_easy_cleanup(_handle);
		_handle = NULL;
	}
}

static int _WriteProgressCallback(void* clientp, double dltotal, double dlnow, double ultotal, double ulnow)
{
	void**					params = (void*)clientp;
	FTPTransferController*	self = (FTPTransferController*)params[0];
	
	if(![self maxLength])
	[self setMaxLength:dltotal];
	
	[self setCurrentLength:dlnow];
	
	return (params[2] ? [[self delegate] fileTransferControllerShouldAbort:self] : 0);
}

static size_t _WriteCallback(void* buffer, size_t size, size_t nmemb, void* userp)
{
	void**					params = (void*)userp;
	FTPTransferController*	self = (FTPTransferController*)params[0];
	NSOutputStream*			stream = (NSOutputStream*)params[1];
	
	return ([self writeToOutputStream:stream bytes:buffer maxLength:(size * nmemb)] ? size * nmemb : -1);
}

- (BOOL) _downloadFileFromPath:(NSString*)remotePath toStream:(NSOutputStream*)stream
{
	NSURL*					url = [self fullAbsoluteURLForRemotePath:remotePath];
	BOOL					success = NO;
	void*					params[3];
	CURLcode				result;
	char					buffer[CURL_ERROR_SIZE];
	NSError*				error;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	params[0] = self;
	params[1] = stream;
	params[2] = ([[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)] ? self : NULL);
	
	_ResetCURLHandle(_handle);
	curl_easy_setopt(_handle, CURLOPT_URL, [[url absoluteString] UTF8String]);
	curl_easy_setopt(_handle, CURLOPT_ERRORBUFFER, buffer);
	curl_easy_setopt(_handle, CURLOPT_WRITEFUNCTION, _WriteCallback);
	curl_easy_setopt(_handle, CURLOPT_WRITEDATA, params);
	curl_easy_setopt(_handle, CURLOPT_NOPROGRESS, (long)0);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSFUNCTION, _WriteProgressCallback);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSDATA, params);
	
	if([self openOutputStream:stream isFileTransfer:YES]) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
		[[self delegate] fileTransferControllerDidStart:self];
		
		result = curl_easy_perform(_handle);
		if(result == CURLE_OK) {
			if([self flushOutputStream:stream]) {
				if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
				[[self delegate] fileTransferControllerDidSucceed:self];
				success = YES;
			}
			else {
				error = [stream streamError];
				[[self delegate] fileTransferControllerDidFail:self withError:([error code] ? error : MAKE_FILETRANSFERCONTROLLER_ERROR(@"Failed flushing output stream (status = %i)", [stream streamStatus]))];
			}
		}
		else {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
			[[self delegate] fileTransferControllerDidFail:self withError:_MakeCURLError(result, buffer)];
		}
		
		[self closeOutputStream:stream];
	}
	
	return success;
}

static int _ReadProgressCallback(void* clientp, double dltotal, double dlnow, double ultotal, double ulnow)
{
	void**					params = (void*)clientp;
	FTPTransferController*	self = (FTPTransferController*)params[0];
	
	[self setCurrentLength:ulnow];
	
	return (params[2] ? [[self delegate] fileTransferControllerShouldAbort:self] : 0);
}

static size_t _ReadCallback(char* bufptr, size_t size, size_t nitems, void* userp)
{
	void**					params = (void*)userp;
	FTPTransferController*	self = (FTPTransferController*)params[0];
	NSInputStream*			stream = (NSInputStream*)params[1];
	
	return [self readFromInputStream:stream bytes:bufptr maxLength:(size * nitems)];
}

- (BOOL) _uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream
{
	NSURL*					url = [self fullAbsoluteURLForRemotePath:remotePath];
	BOOL					success = NO;
	void*					params[3];
	CURLcode				result;
	char					buffer[CURL_ERROR_SIZE];
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	params[0] = self;
	params[1] = stream;
	params[2] = ([[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)] ? self : NULL);
	
	_ResetCURLHandle(_handle);
	curl_easy_setopt(_handle, CURLOPT_URL, [[url absoluteString] UTF8String]);
	curl_easy_setopt(_handle, CURLOPT_ERRORBUFFER, buffer);
	curl_easy_setopt(_handle, CURLOPT_READFUNCTION, _ReadCallback);
	curl_easy_setopt(_handle, CURLOPT_READDATA, params);
	curl_easy_setopt(_handle, CURLOPT_NOPROGRESS, (long)0);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSFUNCTION, _ReadProgressCallback);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSDATA, params);
	curl_easy_setopt(_handle, CURLOPT_UPLOAD, (long)1);
	curl_easy_setopt(_handle, CURLOPT_INFILESIZE, (long)[self maxLength]);
	
	if([self openInputStream:stream isFileTransfer:YES]) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
		[[self delegate] fileTransferControllerDidStart:self];
		
		result = curl_easy_perform(_handle);
		if(result == CURLE_OK) {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
			[[self delegate] fileTransferControllerDidSucceed:self];
			success = YES;
		}
		else {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
			[[self delegate] fileTransferControllerDidFail:self withError:_MakeCURLError(result, buffer)];
		}
		
		[self closeInputStream:stream];
	}
	
	return success;
}

static NSDictionary* _ParseFTPDirectoryListing(NSData* data)
{
	NSMutableDictionary*	result = [NSMutableDictionary dictionary];
	NSUInteger				offset = 0;
	NSMutableDictionary*	dictionary;
	CFDictionaryRef			entry;
	CFIndex					length;
	NSInteger				type;
	
	while(1) {
		length = CFFTPCreateParsedResourceListing(kCFAllocatorDefault, (unsigned char*)[data bytes] + offset, [data length] - offset, &entry);
		if((length <= 0) || (entry == NULL))
		break;
		
		if(![(NSString*)CFDictionaryGetValue(entry, kCFFTPResourceName) isEqualToString:@"."] && ![(NSString*)CFDictionaryGetValue(entry, kCFFTPResourceName) isEqualToString:@".."]) {
			type = [(NSNumber*)CFDictionaryGetValue(entry, kCFFTPResourceType) integerValue];
			
			dictionary = [NSMutableDictionary new];
			if(type == 8) {
				[dictionary setObject:NSFileTypeRegular forKey:NSFileType];
				[dictionary setObject:(id)CFDictionaryGetValue(entry, kCFFTPResourceSize) forKey:NSFileSize];
			}
			else if(type == 4)
			[dictionary setObject:NSFileTypeDirectory forKey:NSFileType];
			[dictionary setObject:(id)CFDictionaryGetValue(entry, kCFFTPResourceModDate) forKey:NSFileModificationDate];
			[result setObject:dictionary forKey:(id)CFDictionaryGetValue(entry, kCFFTPResourceName)];
			[dictionary release];
		}
		
		CFRelease(entry);
		offset += length;
	}
	
	return result;
}

#if __USE_LISTING_PROGRESS__
static int _ListingProgressCallback(void* clientp, double dltotal, double dlnow, double ultotal, double ulnow)
{
	void**					params = (void*)clientp;
	FTPTransferController*	self = (FTPTransferController*)params[1];
	
	return (params[2] ? [[self delegate] fileTransferControllerShouldAbort:self] : 0);
}
#endif

static size_t _ListingCallback(void* buffer, size_t size, size_t nmemb, void* userp)
{
	void**					params = (void*)userp;
	NSMutableData*			data = (NSMutableData*)params[0];
	
	[data appendBytes:buffer length:(size * nmemb)];
	
	return (size * nmemb);
}

- (NSDictionary*) contentsOfDirectoryAtPath:(NSString*)remotePath
{
	NSMutableData*			data = [NSMutableData data];
	NSDictionary*			dictionary = nil;
	NSURL*					url;
	CURLcode				result;
	char					buffer[CURL_ERROR_SIZE];
#if __USE_LISTING_PROGRESS__
	void*					params[3];
#else
	void*					params[1];
#endif
	
	if(remotePath) {
		if(![remotePath hasSuffix:@"/"])
		remotePath = [remotePath stringByAppendingString:@"/"];
	}
	else
	remotePath = @"/";
	url = [self fullAbsoluteURLForRemotePath:remotePath];
	
	params[0] = data;
#if __USE_LISTING_PROGRESS__
	params[1] = self;
	params[2] = ([[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)] ? self : NULL);
#endif
	
	_ResetCURLHandle(_handle);
	curl_easy_setopt(_handle, CURLOPT_URL, [[url absoluteString] UTF8String]);
	curl_easy_setopt(_handle, CURLOPT_ERRORBUFFER, buffer);
	curl_easy_setopt(_handle, CURLOPT_WRITEFUNCTION, _ListingCallback);
	curl_easy_setopt(_handle, CURLOPT_WRITEDATA, params);
#if __USE_LISTING_PROGRESS__
	curl_easy_setopt(_handle, CURLOPT_NOPROGRESS, (long)0);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSFUNCTION, _ListingProgressCallback);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSDATA, params);
#else
	curl_easy_setopt(_handle, CURLOPT_NOPROGRESS, (long)1);
#endif
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	result = curl_easy_perform(_handle);
	if(result == CURLE_OK) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
		[[self delegate] fileTransferControllerDidSucceed:self];
		dictionary = _ParseFTPDirectoryListing(data);
	}
	else {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:_MakeCURLError(result, buffer)];
	}
	
	return dictionary;
}

#if __USE_COMMAND_PROGRESS__
static int _CommandProgressCallback(void* clientp, double dltotal, double dlnow, double ultotal, double ulnow)
{
	void**					params = (void*)clientp;
	FTPTransferController*	self = (FTPTransferController*)params[0];
	
	return (params[1] ? [[self delegate] fileTransferControllerShouldAbort:self] : 0);
}
#endif

/* This method takes ownership of the header list */
- (BOOL) _performCommands:(struct curl_slist*)headerList withURL:(NSURL*)url
{
	BOOL					success = NO;
	CURLcode				result;
	char					buffer[CURL_ERROR_SIZE];
	FILE*					file;
#if __USE_COMMAND_PROGRESS__
	void*					params[2];
#endif
	
#if __USE_COMMAND_PROGRESS__
	params[0] = self;
	params[1] = ([[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)] ? self : NULL);
#endif
	file = fopen("/dev/null", "a");
	
	_ResetCURLHandle(_handle);
	curl_easy_setopt(_handle, CURLOPT_URL, [[url absoluteString] UTF8String]);
	curl_easy_setopt(_handle, CURLOPT_ERRORBUFFER, buffer);
	curl_easy_setopt(_handle, CURLOPT_WRITEDATA, file);
#if __USE_COMMAND_PROGRESS__
	curl_easy_setopt(_handle, CURLOPT_NOPROGRESS, (long)0);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSFUNCTION, _CommandProgressCallback);
	curl_easy_setopt(_handle, CURLOPT_PROGRESSDATA, params);
#else
	curl_easy_setopt(_handle, CURLOPT_NOPROGRESS, (long)1);
#endif
	curl_easy_setopt(_handle, CURLOPT_NOBODY, (long)1);
	curl_easy_setopt(_handle, CURLOPT_QUOTE, headerList);
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	result = curl_easy_perform(_handle);
	if(result == CURLE_OK) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
		[[self delegate] fileTransferControllerDidSucceed:self];
		success = YES;
	}
	else {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:_MakeCURLError(result, buffer)];
	}
	
	curl_slist_free_all(headerList);
	fclose(file);
	
	return success;
}

- (BOOL) movePath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath
{
	struct curl_slist*		headerList = NULL;
	
	headerList = curl_slist_append(headerList, [[NSString stringWithFormat:@"RNFR %@", [self absolutePathForRemotePath:fromRemotePath]] UTF8String]);
	headerList = curl_slist_append(headerList, [[NSString stringWithFormat:@"RNTO %@", [self absolutePathForRemotePath:toRemotePath]] UTF8String]);
	
	return [self _performCommands:headerList withURL:[self fullAbsoluteURLForRemotePath:nil]];
}

- (BOOL) createDirectoryAtPath:(NSString*)remotePath
{
	struct curl_slist*		headerList = NULL;
	
	headerList = curl_slist_append(headerList, [[NSString stringWithFormat:@"MKD %@", [self absolutePathForRemotePath:remotePath]] UTF8String]);
	
	return [self _performCommands:headerList withURL:[self fullAbsoluteURLForRemotePath:nil]];
}

- (BOOL) deleteFileAtPath:(NSString*)remotePath
{
	struct curl_slist*		headerList = NULL;
	
	headerList = curl_slist_append(headerList, [[NSString stringWithFormat:@"DELE %@", [self absolutePathForRemotePath:remotePath]] UTF8String]);
	
	return [self _performCommands:headerList withURL:[self fullAbsoluteURLForRemotePath:nil]];
}

- (BOOL) deleteDirectoryAtPath:(NSString*)remotePath
{
	struct curl_slist*		headerList = NULL;
	
	headerList = curl_slist_append(headerList, [[NSString stringWithFormat:@"RMD %@", [self absolutePathForRemotePath:remotePath]] UTF8String]);
	
	return [self _performCommands:headerList withURL:[self fullAbsoluteURLForRemotePath:nil]];
}

@end

@implementation FTPSTransferController

+ (NSString*) urlScheme;
{
	return @"ftps";
}

@end
