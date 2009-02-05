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

#import <zlib.h>

#import "NSData+GZip.h"

#define kChunkSize	(128 * 1024) //128Kb

@implementation NSData (GZip)

- (NSData*) compressGZip
{
	uLong			length = compressBound([self length]);
	NSMutableData*	data = [NSMutableData dataWithLength:(sizeof(unsigned int) + length)];
	
	if(compress2((unsigned char*)[data mutableBytes] + sizeof(unsigned int), &length, [self bytes], [self length], Z_BEST_COMPRESSION) != Z_OK)
	return nil;
	
	*((unsigned int*)[data mutableBytes]) = NSSwapHostIntToBig([self length]);
	[data setLength:(sizeof(unsigned int) + length)];
	
	return data;
}

- (NSData*) decompressGZip
{
	uLong			length = NSSwapBigIntToHost(*((unsigned int*)[self bytes]));
	NSMutableData*	data = [NSMutableData dataWithLength:length];
	
	if(uncompress([data mutableBytes], &length, (unsigned char*)[self bytes] + sizeof(unsigned int), [self length] - sizeof(unsigned int)) != Z_OK)
	return nil;
	
	return data;
}

- (id) initWithGZipFile:(NSString*)path
{
	const char*		string = [path UTF8String];
	BOOL			success = NO;
	gzFile			file;
	int				result;
	size_t			length;
	char*			buffer;
	
	file = gzopen(string, "r");
	if(file != NULL) {
		length = kChunkSize;
		buffer = malloc(length);
		while(1) {
			result = gzread(file, buffer + length - kChunkSize, kChunkSize);
			if(result < 0)
			break;
			if(result < kChunkSize) {
				length -= kChunkSize - result;
				buffer = realloc(buffer, length);
				break;
			}
			length += kChunkSize;
			buffer = realloc(buffer, length);
		}
		
		if(result >= 0) {
			if((self = [self initWithBytesNoCopy:buffer length:length freeWhenDone:YES]))
			success = YES;
			else
			free(buffer);
		}
		else
		free(buffer);
		
		gzclose(file);
	}
	
	if(success == NO) {
		[self release];
		return nil;
	}
	
	return self;
}

- (BOOL) writeToGZipFile:(NSString*)path
{
	const char*		string = [path UTF8String];
	BOOL			success = NO;
	gzFile			file;
	
	file = gzopen(string, "w9f"); //Stategy is f, h or R - 9 is Z_BEST_COMPRESSION
	if(file == NULL)
	return NO;
	
	if(gzwrite(file, [self bytes], [self length]) == [self length])
	success = YES;
	
	gzclose(file);
	
	if(success == NO)
	unlink(string);
	
	return success;
}

@end
