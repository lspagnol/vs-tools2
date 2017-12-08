function file
{

if [ "$1" == "help" ] ; then cat<<EOF

DESCRIPTION

	'file' related functions

SUB-FUNCTIONS

	fileExists <file>
	fileExistsQuiet <file>
	fileNotExists <file>

USAGE

	For help about sub-functions, use '<sub-function> help'

EOF
exit 1
fi

# WRAPPER
# Appeler la commande /usr/bin/file et passer les arguments
/usr/bin/file $@

}

function fileExists
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	fileExists

SYNOPSIS

	fileExists <file>

DESCRIPTION

	Check if <file> exists.

	Return code: 0 if success or log as error.

EOF
exit 1
fi

test -n "$1" || { error "$E_120" ; return 1 ; }
test -f $1 || { error "$E_121 ($1)" ; return 1 ; }

return 0

}

function fileNotExists
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	fileNotExists

SYNOPSIS

	fileNotExists <file>

DESCRIPTION

	Check if <file> not exists.

	Return code: 0 if success or log as error.

EOF
exit 1
fi

test -n "$1" || { error "$E_120" ; return 1 ; }
test -f $1 && { error "$E_122 ($1)" ; return 1 ; }

return 0

}

function fileExistsQuiet
{

if [ "$1" == "help" ] ; then cat<<EOF

NAME

	fileExistsQuiet

SYNOPSIS

	fileExistsQuiet <file>

DESCRIPTION

	Check if <file> exists.

	Return code: 0 if success.

EOF
exit 1
fi

test -n "$1" || { error "$E_120" ; return 1 ; }
test -f $1 || return 1

return 0

}
