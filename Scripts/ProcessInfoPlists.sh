#####
#
# This script replaces __NAME__, __VERSION__ and __SVN_REVISION__ by their actual values in the Info.plist and InfoPlist.strings files for the target
# 
# The project file must have a "version" SVN property defined as such:
# > svn propset version 1.0b1 Myproject.xcodeproj/project.pbxproj
#
# To use in a target, add a script phase with this single line:
# ${SRCROOT}/PolKit/Scripts/ProcessInfoPlists.sh
#
#####

# Retrieve version and revision from SVN
REVISION=`svn info "${PROJECT_DIR}"`
if [[ $? -ne 0 ]]
then
	VERSION="(undefined)"
	REVISION="0"
else
	VERSION=`svn propget version "${PROJECT_FILE_PATH}/project.pbxproj"`
	REVISION=`svn info "${PROJECT_DIR}" | grep "Revision:" | awk '{ print $2 }'`
fi
NAME="$PRODUCT_NAME"

# Patch Info.plist
PATH="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
/usr/bin/perl -p -e "s/__NAME__/$NAME/g" "$PATH" > "$PATH~"
/bin/mv "$PATH~" "$PATH"
/usr/bin/perl -p -e "s/__VERSION__/$VERSION/g" "$PATH" > "$PATH~"
/bin/mv "$PATH~" "$PATH"
/usr/bin/perl -p -e "s/__SVN_REVISION__/$REVISION/g" "$PATH" > "$PATH~"
/bin/mv "$PATH~" "$PATH"

# Patch InfoPlist.strings
cd "${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
for LANGUAGE in *.lproj;
do
	PATH="$LANGUAGE${INFOSTRINGS_PATH}"
	/usr/bin/textutil -format txt -inputencoding UTF-16 -convert txt -encoding UTF-8 "$PATH" -output "$PATH"
	/usr/bin/perl -p -e "s/__NAME__/$NAME/g" "$PATH" > "$PATH~"
	/bin/mv "$PATH~" "$PATH"
	/usr/bin/perl -p -e "s/__VERSION__/$VERSION/g" "$PATH" > "$PATH~"
	/bin/mv "$PATH~" "$PATH"
	/usr/bin/perl -p -e "s/__SVN_REVISION__/$REVISION/g" "$PATH" > "$PATH~"
	/bin/mv "$PATH~" "$PATH"
	/usr/bin/textutil -format txt -inputencoding UTF-8 -convert txt -encoding UTF-16 "$PATH" -output "$PATH"
done
