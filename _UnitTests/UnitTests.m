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

#import <objc/runtime.h>
#import <libgen.h>

#import "UnitTests.h"

#define kSystemPrefix		"/System/"
#define kLibraryPrefix		"/Library/"
#define kUsrPrefix			"/usr/"
#define kMethodPrefix		"test"
#define kResourceDirectory	"Resources"

@implementation UnitTest

@synthesize didFail=_didFail;

- (void) logFailure:(NSString*)message, ...
{
	NSString*				string;
	va_list					list;
	
	va_start(list, message);
	string = [[NSString alloc] initWithFormat:message arguments:list];
	fprintf(stderr, "\t");
	fprintf(stderr, [[string stringByReplacingOccurrencesOfString:@"\n" withString:@"\n\t"] UTF8String]);
	fprintf(stderr, "\n");
	[string release];
	va_end(list);
	
	_didFail = YES;
}

@end

int main(int argc, const char* argv[])
{
	NSUInteger				total = 0,
							failures = 0;
	unsigned int			count1,
							i1,
							count2,
							i2,
							count3,
							i3;
	const char**			images;
	const char**			classes;
	Method*					methods;
	NSAutoreleasePool*		localPool;
	Class					class;
	UnitTest*				test;
	int						i;
	SEL						method;
	int						match;
	char					path[PATH_MAX];
	BOOL					didFail;
	
	if(argv[0][0] != '/')
	return 1;
	sprintf(path, "%s/%s", dirname((char*)argv[0]), kResourceDirectory);
	printf("%s\n", path);
	if(chdir(path) != 0)
	return 1;
	
	printf("===== UNIT TESTS STARTED =====\n");
	
	images = objc_copyImageNames(&count1);
	for(i1 = 0; i1 < count1; ++i1) {
		if(strncmp(images[i1], kSystemPrefix, strlen(kSystemPrefix)) == 0)
		continue;
		if(strncmp(images[i1], kLibraryPrefix, strlen(kLibraryPrefix)) == 0)
		continue;
		if(strncmp(images[i1], kUsrPrefix, strlen(kUsrPrefix)) == 0)
		continue;
		
		classes = objc_copyClassNamesForImage(images[i1], &count2);
		for(i2 = 0; i2 < count2; ++i2) {
			class = objc_getClass(classes[i2]);
			do {
				class = class_getSuperclass(class);
			} while(class && (class != objc_getClass("UnitTest")));
			if(class == nil)
			continue;
			class = objc_getClass(classes[i2]);
			
			match = 0;
			for(i = 1; i < argc; ++i) {
				if(strncmp(argv[i], kMethodPrefix, strlen(kMethodPrefix)) != 0) {
					match = -1;
					if(strcmp(argv[i], classes[i2]) == 0) {
						match = 1;
						break;
					}
				}
			}
			if(match < 0)
			continue;
			
			methods = class_copyMethodList(class, &count3);
			for(i3 = 0; i3 < count3; ++i3) {
				method = method_getName(methods[i3]);
				if(strncmp(sel_getName(method), kMethodPrefix, strlen(kMethodPrefix)) != 0)
				continue;
				
				match = 0;
				for(i = 1; i < argc; ++i) {
					if(strncmp(argv[i], kMethodPrefix, strlen(kMethodPrefix)) == 0) {
						match = -1;
						if(strcmp(argv[i], sel_getName(method)) == 0) {
							match = 1;
							break;
						}
					}
				}
				if(match < 0)
				continue;
				
				printf("-[%s %s]\n", classes[i2], sel_getName(method));
				localPool = [NSAutoreleasePool new];
				@try {
					test = [class new];
					[test performSelector:method];
					didFail = [test didFail];
					[test release];
					if(didFail)
					++failures;
				}
				@catch(NSException* exception) {
					printf("<IGNORED EXCEPTION> %s\n", [[exception description] UTF8String]);
					++failures;
				}
				++total;
				[localPool release];
			}
		}
	}
	
	printf("===== %i UNIT TESTS COMPLETED WITH %i FAILURE(S) =====\n", total, failures);
	
	return 0;
}
