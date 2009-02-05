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

#import "FileTransferController_Internal.h"
#import "NSURL+Parameters.h"

@implementation FTPTransferController

+ (NSString*) urlScheme;
{
	return @"ftp";
}

- (id) processReadResultStream:(NSOutputStream*)stream userInfo:(id)info error:(NSError**)error
{
	NSData*					data = [stream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
	id						result = nil;
	NSUInteger				offset = 0;
	NSMutableDictionary*	dictionary;
	CFDictionaryRef			entry;
	CFIndex					length;
	NSInteger				type;
	
	if(info == [NSNull null]) {
		result = [NSMutableDictionary dictionary];
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
	}
	else
	result = [NSNumber numberWithBool:YES];
	
	return result;
}

- (void) readStreamClientCallBack:(CFReadStreamRef)stream type:(CFStreamEventType)type
{
	CFNumberRef					value;
	
	switch(type) {
		
		case kCFStreamEventOpenCompleted:
		value = CFReadStreamCopyProperty(stream, kCFStreamPropertyFTPResourceSize);
		if(value) {
			[self setMaxLength:[(NSNumber*)value unsignedIntegerValue]];
			CFRelease(value);
		}
		else
		[self setMaxLength:0];
		break;
		
	}
	
	[super readStreamClientCallBack:stream type:type];
}

- (CFReadStreamRef) _createReadStreamWithPath:(NSString*)path
{
	NSURL*					url = [self absoluteURLForRemotePath:path];
	NSString*				user = [[self baseURL] user];
	NSString*				password = [[self baseURL] passwordByReplacingPercentEscapes];
	CFReadStreamRef			readStream;
	CFDictionaryRef			proxySettings;
	
	readStream = CFReadStreamCreateWithFTPURL(kCFAllocatorDefault, (CFURLRef)url);
	if(readStream == NULL)
	return NULL;
	CFReadStreamSetProperty(readStream, kCFStreamPropertyFTPUsePassiveMode, kCFBooleanTrue);
	CFReadStreamSetProperty(readStream, kCFStreamPropertyFTPAttemptPersistentConnection, kCFBooleanFalse);
	CFReadStreamSetProperty(readStream, kCFStreamPropertyFTPFetchResourceInfo, kCFBooleanTrue);
	
	if(user) {
		CFReadStreamSetProperty(readStream, kCFStreamPropertyFTPUserName, (CFStringRef)user);
		if(password)
		CFReadStreamSetProperty(readStream, kCFStreamPropertyFTPPassword, (CFStringRef)password);
	}
	
	if((proxySettings = SCDynamicStoreCopyProxies(NULL))) {
		CFReadStreamSetProperty(readStream, kCFStreamPropertyFTPProxy, (proxySettings));
		CFRelease(proxySettings);
	}
	
	return readStream;
}

- (NSDictionary*) contentsOfDirectoryAtPath:(NSString*)remotePath
{
	CFReadStreamRef			readStream;
	
	if(remotePath) {
		if(![remotePath hasSuffix:@"/"])
		remotePath = [remotePath stringByAppendingString:@"/"];
	}
	else
	remotePath = @"/";
	
	readStream = [self _createReadStreamWithPath:remotePath];
	if(readStream == NULL)
	return nil;
	
	return [self runReadStream:readStream dataStream:[NSOutputStream outputStreamToMemory] userInfo:[NSNull null] isFileTransfer:NO];
}

- (BOOL) downloadFileFromPath:(NSString*)remotePath toStream:(NSOutputStream*)stream
{
	CFReadStreamRef			readStream;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	readStream = [self _createReadStreamWithPath:remotePath];
	if(readStream == NULL)
	return NO;
	
	return [[self runReadStream:readStream dataStream:stream userInfo:nil isFileTransfer:YES] boolValue];
}

- (CFWriteStreamRef) _createWriteStreamWithPath:(NSString*)path
{
	NSURL*					url = [self absoluteURLForRemotePath:path];
	NSString*				user = [[self baseURL] user];
	NSString*				password = [[self baseURL] passwordByReplacingPercentEscapes];
	CFWriteStreamRef		writeStream;
	CFDictionaryRef			proxySettings;
	
	writeStream = CFWriteStreamCreateWithFTPURL(kCFAllocatorDefault, (CFURLRef)url);
	if(writeStream == NULL)
	return NULL;
	CFWriteStreamSetProperty(writeStream, kCFStreamPropertyFTPUsePassiveMode, kCFBooleanTrue);
	CFWriteStreamSetProperty(writeStream, kCFStreamPropertyFTPAttemptPersistentConnection, kCFBooleanFalse);
	
	if(user) {
		CFWriteStreamSetProperty(writeStream, kCFStreamPropertyFTPUserName, (CFStringRef)user);
		if(password)
		CFWriteStreamSetProperty(writeStream, kCFStreamPropertyFTPPassword, (CFStringRef)password);
	}
	
	if((proxySettings = SCDynamicStoreCopyProxies(NULL))) {
		CFWriteStreamSetProperty(writeStream, kCFStreamPropertyFTPProxy, (proxySettings));
		CFRelease(proxySettings);
	}
	
	[self setMaxLength:0];
	
	return writeStream;
}

- (BOOL) uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream
{
	CFWriteStreamRef		writeStream;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	writeStream = [self _createWriteStreamWithPath:remotePath];
	if(writeStream == NULL)
	return NO;
	
	return [[self runWriteStream:writeStream dataStream:stream userInfo:nil isFileTransfer:YES] boolValue];
}

- (BOOL) createDirectoryAtPath:(NSString*)remotePath
{
	CFWriteStreamRef			writeStream;
	
	if(![remotePath hasSuffix:@"/"])
	remotePath = [remotePath stringByAppendingString:@"/"];
	
	writeStream = [self _createWriteStreamWithPath:remotePath];
	if(writeStream == NULL)
	return NO;
	
	return [[self runWriteStream:writeStream dataStream:nil userInfo:nil isFileTransfer:NO] boolValue];
}

- (BOOL) _deletePath:(NSString*)remotePath
{
	CFWriteStreamRef			writeStream;
	
	writeStream = [self _createWriteStreamWithPath:remotePath];
	if(writeStream == NULL)
	return NO;
	CFWriteStreamSetProperty(writeStream, CFSTR("_kCFStreamPropertyFTPRemoveResource"), kCFBooleanTrue);
	
	return [[self runWriteStream:writeStream dataStream:nil userInfo:nil isFileTransfer:NO] boolValue];
}

- (BOOL) deleteFileAtPath:(NSString*)remotePath
{
	return [self _deletePath:remotePath];
}

- (BOOL) deleteDirectoryAtPath:(NSString*)remotePath
{
	if(![remotePath hasSuffix:@"/"])
	remotePath = [remotePath stringByAppendingString:@"/"];
	
	return [self _deletePath:remotePath];
}

@end
