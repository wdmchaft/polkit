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

#import <sys/mount.h>

#import "FileTransferController_Internal.h"
#import "NSURL+Parameters.h"

@implementation LocalTransferController

+ (BOOL) useAsyncStreams
{
	return NO;
}

+ (NSString*) urlScheme
{
	return @"file";
}

- (id) processReadResultStream:(NSOutputStream*)stream userInfo:(id)info error:(NSError**)error
{
	return [NSNumber numberWithBool:YES];
}

- (NSDictionary*) contentsOfDirectoryAtPath:(NSString*)remotePath
{
	NSURL*					url = [self absoluteURLForRemotePath:remotePath];
	NSFileManager*			manager = [NSFileManager defaultManager];
	NSMutableDictionary*	dictionary;
	NSError*				error;
	NSArray*				array;
	NSString*				path;
	NSMutableDictionary*	entry;
	NSDictionary*			info;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	array = [manager contentsOfDirectoryAtPath:[url path] error:&error];
	if(array == nil) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:error];
		return nil;
	}
	
	dictionary = [NSMutableDictionary dictionary];
	for(path in array) {
		info = [manager attributesOfItemAtPath:[[url path] stringByAppendingPathComponent:path] error:&error];
		if(info == nil) {
			NSLog(@"%s: %@", __FUNCTION__, error);
			continue; //FIXME: Is this the best behavior?
		}
		
		entry = [NSMutableDictionary new];
		[entry setValue:[info objectForKey:NSFileType] forKey:NSFileType];
		[entry setValue:[info objectForKey:NSFileCreationDate] forKey:NSFileCreationDate];
		[entry setValue:[info objectForKey:NSFileModificationDate] forKey:NSFileModificationDate];
		[entry setValue:[info objectForKey:NSFileSize] forKey:NSFileSize];
		[dictionary setObject:entry forKey:path];
		[entry release];
	}
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
	[[self delegate] fileTransferControllerDidSucceed:self];
	
	return dictionary;
}

- (BOOL) createDirectoryAtPath:(NSString*)remotePath
{
	NSURL*					url = [self absoluteURLForRemotePath:remotePath];
	NSError*				error;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if(![[NSFileManager defaultManager] createDirectoryAtPath:[url path] withIntermediateDirectories:NO attributes:nil error:&error]) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:error];
		return NO;
	}
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
	[[self delegate] fileTransferControllerDidSucceed:self];
	
	return YES;
}

- (BOOL) _downloadFileFromPath:(NSString*)remotePath toStream:(NSOutputStream*)stream
{
	NSURL*					url = [self absoluteURLForRemotePath:remotePath];
	NSDictionary*			info;
	NSError*				error;
	CFReadStreamRef			readStream;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	info = [[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:&error];
	if(info == nil)
	return NO;
	[self setMaxLength:[[info objectForKey:NSFileSize] unsignedIntegerValue]];
	
	readStream = CFReadStreamCreateWithFile(kCFAllocatorDefault, (CFURLRef)url);
	if(readStream == NULL)
	return NO;
	
	return [[self runReadStream:readStream dataStream:stream userInfo:nil isFileTransfer:YES] boolValue];
}

- (BOOL) _uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream
{
	NSURL*					url = [self absoluteURLForRemotePath:remotePath];
	CFWriteStreamRef		writeStream;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	writeStream = CFWriteStreamCreateWithFile(kCFAllocatorDefault, (CFURLRef)url);
	if(writeStream == NULL)
	return NO;
	
	return [[self runWriteStream:writeStream dataStream:stream userInfo:nil isFileTransfer:YES] boolValue];
}

- (BOOL) movePath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath
{
	NSURL*					fromURL = [self absoluteURLForRemotePath:fromRemotePath];
	NSURL*					toURL = [self absoluteURLForRemotePath:toRemotePath];
	NSFileManager*			manager = [NSFileManager defaultManager];
	NSError*				error;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if([manager fileExistsAtPath:[toURL path]] && ![manager removeItemAtPath:[toURL path] error:&error]) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:error];
		return NO;
	}
	
	if(![manager moveItemAtPath:[fromURL path] toPath:[toURL path] error:&error]) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:error];
		return NO;
	}
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
	[[self delegate] fileTransferControllerDidSucceed:self];
	
	return YES;
}

- (BOOL) copyPath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath
{
	NSURL*					fromURL = [self absoluteURLForRemotePath:fromRemotePath];
	NSURL*					toURL = [self absoluteURLForRemotePath:toRemotePath];
	NSFileManager*			manager = [NSFileManager defaultManager];
	NSError*				error;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if([manager fileExistsAtPath:[toURL path]] && ![manager removeItemAtPath:[toURL path] error:&error]) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:error];
		return NO;
	}
	
	if(![manager copyItemAtPath:[fromURL path] toPath:[toURL path] error:&error]) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:error];
		return NO;
	}
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
	[[self delegate] fileTransferControllerDidSucceed:self];
	
	return YES;
}

- (BOOL) _deletePath:(NSString*)remotePath
{
	NSURL*					url = [self absoluteURLForRemotePath:remotePath];
	NSFileManager*			manager = [NSFileManager defaultManager];
	NSError*				error;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	if([manager fileExistsAtPath:[url path]] && ![manager removeItemAtPath:[url path] error:&error]) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:error];
		return NO;
	}
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
	[[self delegate] fileTransferControllerDidSucceed:self];
	
	return YES;
}

- (BOOL) deleteFileAtPath:(NSString*)remotePath
{
	return [self _deletePath:remotePath];
}

- (BOOL) deleteDirectoryRecursivelyAtPath:(NSString*)remotePath
{
	return [self _deletePath:remotePath];
}

- (BOOL) isLocalDisk
{
	return YES;
}

@end

@implementation FileTransferController (LocalTransferController)

- (BOOL) isLocalDisk
{
	return NO;
}

@end

@implementation RemoteTransferController

+ (const char*) fileSystemName
{
	[self doesNotRecognizeSelector:_cmd];
	return NULL;
}

- (id) initWithBaseURL:(NSURL*)url
{
	OSStatus				error;
	FSRef					directory;
	NSURL*					volumeURL;
	NSString*				path;
	NSMutableArray*			components;
	struct statfs			info;
	
	if((self = [super initWithBaseURL:url])) {
		components = [NSMutableArray arrayWithArray:[[url path] pathComponents]];
		[components removeObjectAtIndex:0];
		if([components count] == 0) {
			[self release];
			return nil;
		}
		volumeURL = [NSURL URLWithScheme:[[self class] urlScheme] user:nil password:nil host:[url host] port:0 path:[components objectAtIndex:0]];
		[components removeObjectAtIndex:0];
		
		path = [@"/Volumes" stringByAppendingPathComponent:[volumeURL path]];
		if((statfs([path UTF8String], &info) == 0) && (strcmp(info.f_fstypename, [[self class] fileSystemName]) == 0))
		_basePath = ([components count] ? [[path stringByAppendingPathComponent:[NSString pathWithComponents:components]] copy] : [path copy]);
		else {
			error = FSMountServerVolumeSync((CFURLRef)volumeURL, NULL, (CFStringRef)[url user], (CFStringRef)[url passwordByReplacingPercentEscapes], &_volumeRefNum, 0);
			if(error != noErr)
			NSLog(@"%s: FSMountServerVolumeSync() failed with error %i", __FUNCTION__, error);
			else {
				error = FSGetVolumeInfo(_volumeRefNum, 0, NULL, kFSVolInfoNone, NULL, NULL, &directory);
				if(error != noErr)
				NSLog(@"%s: FSGetVolumeInfo() failed with error %i", __FUNCTION__, error);
				else {
					path = [[(id)CFURLCreateFromFSRef(kCFAllocatorDefault, &directory) autorelease] path];
					if(path == nil) {
						NSLog(@"%s: CFURLCreateFromFSRef() failed", __FUNCTION__);
						error = -1;
					}
					else
					_basePath = ([components count] ? [[path stringByAppendingPathComponent:[NSString pathWithComponents:components]] copy] : [path copy]);
				}
			}
			
			if(error != noErr) {
				[self release];
				return nil;
			}
		}
	}
	
	return self;
}

- (void) dealloc
{
	pid_t					dissenter;
	OSStatus				error;
	
	[_basePath release];
	
	if(_volumeRefNum) {
		error = FSUnmountVolumeSync(_volumeRefNum, 0, &dissenter);
		if(error != noErr)
		NSLog(@"%s: FSUnmountVolumeSync() failed with error %i", __FUNCTION__, error);
	}
	
	[super dealloc];
}

/* Override completely */
- (NSURL*) absoluteURLForRemotePath:(NSString*)path
{
	return [NSURL fileURLWithPath:[_basePath stringByAppendingPathComponent:path]];
}

/* Override completely */
- (BOOL) isLocalDisk
{
	return NO;
}

@end

@implementation AFPTransferController

+ (NSString*) urlScheme
{
	return @"afp";
}

+ (const char*) fileSystemName
{
	return "afpfs";
}

@end

@implementation SMBTransferController

+ (NSString*) urlScheme
{
	return @"smb";
}

+ (const char*) fileSystemName
{
	return "smbfs";
}

@end
