function dir
{

if [ "$1" == "help" ] ; then cat<<EOF

DESCRIPTION

	'dir' related functions

SUB-FUNCTIONS

	dirExists <dir>
	dirExistsQuiet <dir>
	dirNotExists <dir>

USAGE

	For help about sub-functions, use '<sub-function> help'

EOF
exit 1
fi

}

function dirExists
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	dirExists

SYNOPSIS

	dirExists <dir>

DESCRIPTION

	Check if <dir> exists.

	Return code: 0 if success or log as error.

EOF
exit 1
fi

test -n "$1" || { error "$E_140" ; return 1 ; }
test -d $1 || { error "$E_141 ($1)" ; return 1 ; }

return 0

}

function dirNotExists
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	dirNotExists

SYNOPSIS

	dirNotExists <dir>

DESCRIPTION

	Check if <dir> exists.

	Return code: 0 if success or log as error.

EOF
exit 1
fi

test -n "$1" || { error "$E_140" ; return 1 ; }
test -d $1 && { error "$E_142 ($1)" ; return 1 ; }

return 0

}

function dirExistsQuiet
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	dirExistsQuiet

SYNOPSIS

	dirExistsQuiet <dir>

DESCRIPTION

	Check if <dir> exists.

	Return code: 0 if success.

EOF
exit 1
fi

test -n "$1" || { error "$E_140" ; return 1 ; }
test -d $1 || return 1

return 0

}
