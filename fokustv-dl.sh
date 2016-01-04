#!/bin/bash

# Define help function
function help(){
    echo "Fokustv-dl - Script to download videos from fokus.tv";
    echo "Usage example:";
    echo "$SCRIPT_NAME [(-h|--help)] [(-v|--verbose)] [(-V|--version)] [(-r|--resume)] [(-p|--parallels) integer] [(-q|--quality) integer] [URLs]";
    echo "Options:";
    echo "-h or --help: Displays this information.";
    echo "-v or --verbose: Verbose mode on.";
    echo "-V or --version: Displays the current version number.";
    echo "-r or --resume path: resume from the last unfinished download. You must set path to tmp directory, what you want reume."
    echo "-p or --parallels integer: Number of download threads, default 16.";
    echo '-q or --quality integer: Quality, options: '$(printf "\"%s\", " "${possible_quality[@]}");
    echo
    echo "If you miss URLs, you can type it from STDIN";
    exit 1;
}
 
# Declare vars. Flags initalizing to 0.
SCRIPT_NAME="$(basename ${0})"
verbose=0;
version=0;
resume=0;

possible_quality=("Full HD" "HD" "standard" "średnia" "niska");
quality="Full HD";
parallels=16;

wgetcmd="wget -q";

# Execute getopt
ARGS=$(getopt -o "hvVr:p:q:" -l "help,verbose,version,resume:,parallels:,quality:" -n "Fokustv-dl" -- "$@");
 
#Bad arguments
if [ $? -ne 0 ];
then
    help;
fi
 
eval set -- "$ARGS";
 
while true; do
    case "$1" in
        -h|--help)
            shift;
            help;
            ;;
        -v|--verbose)
            shift;
                    verbose="1";
            ;;
        -V|--version)
            shift;
                    echo "Version: 0.2";
                    exit 0;
            ;;
        -p|--parallels)
            shift;
                    if [ -n "$1" ]; 
                    then
                        parallels="$1";
                        shift;
                    fi
            ;;
        -r|--resume)
            shift;
                    if [ -n "$1" ]; 
                    then
                        resume="$1";
                        shift;
                    fi
            ;;
        -q|--quality)
            shift;
                    if [ -n "$1" ]; 
                    then
                        quality="$1";
                        shift;
                    fi
            ;;
        --)
            shift;
            break;
            ;;
    esac
done

# Check required arguments

if [[ $verbose -eq 1 ]]; then
    wgetcmd="wget"
fi;

# Check required software
command -v wget >/dev/null 2>&1 || { echo >&2 "I require wget but it's not installed. Aborting."; exit 1; }
command -v parallel >/dev/null 2>&1 || { echo >&2 "I require parallel but it's not installed. Aborting."; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo >&2 "I require ffmpeg but it's not installed. Aborting."; exit 1; }

# Check parallels version
parallels_version=$(parallel -V | head -n 1 | sed 's/GNU parallel //');
if [[ $parallels_version -ge '20131122' ]]; then
    parallels_options="parallel -j $parallels --halt 1 --bar --no-notice --tag --res logs --resume-failed";
elif [[ $parallels_version -ge '20111022' ]]; then
    echo "Warning: You using old parallel version, this version isn't full compatible. "
    parallels_options="parallel -j $parallels --halt 1 --progress --no-notice --joblog logs --resume";
fi

if [[ -z $@ ]]; then
    echo "Write one URL per line, if end press Ctrl+D or empty line:"
    while read -r -p "URL: "; do [[ $REPLY ]] || break; url_array+=("$REPLY"); done
else
    url_array=$@
fi

if [[ "$resume" != 0 ]]; then
    if [[ ${#url_array[@]} != 1 ]]; then
        echo "Error: If you want to resume, you can give only one link!";
        exit 1;
    fi;
fi

for url in ${url_array[@]}; do
    if [[ "$resume" != 0 ]]; then
        if [ ! -d "$resume" ]; then
            echo "Error: Resume path: $path not exis";
            exit 1;
        fi
    
        cd "$resume";
    else 
        tempdir=$(mktemp -d -p "$PWD");
        cd $tempdir;
    fi

    data=$($wgetcmd -O - "$url" | sed -ne '/.*playlist: \[{$/,/.*}],.*/p') || exit 1;
    if [[ $verbose -eq 1 ]]; then
        echo "$data"
    fi
    playlist_url=$(echo "$data" | grep -Po "url: '\K[^']*") || exit 1;
    title=$(echo "$data" | grep -Po "title: '\K[^']*") || exit 1;
    playlist=$($wgetcmd -O - "$playlist_url") || exit 1;
    
    if [[ $verbose -eq 1 ]]; then
        echo "$playlist"
    fi

    IFS_backup=$IFS
    IFS=$'\n'
    quality_options=($(echo "$playlist" | grep -Po 'NAME="\K[^"]*'))
    quality_url=($(echo "$playlist" | grep http))
    
    i=0
    for option in ${quality_options[@]}; do
        if [[ $verbose -eq 1 ]]; then
            echo "\$option=$option"
            echo "\$quality=$quality"
        fi
        if [ $option = $quality ]; then
            quality_id_select=$i;
            break;
        fi;
        $(i++);
    done;
    echo "Download: $title";
    if [[ -z $quality_id_select ]]; then
        echo "Your quality ($quality) is not available for this video, so I download ${quality_options[0]}";
        quality_id=0;
    else 
        quality_id=$quality_id_select;
    fi
    
    IFS=$IFS_backup
    
    videoslist=$($wgetcmd -O - "${quality_url[$quality_id]}") || exit 1;

    if [[ $verbose -eq 1 ]]; then
        echo "$videoslist"
    fi

    

    echo "$videoslist" | grep http | $parallels_options wget -c --tries=0 --timeout=5 -q || exit 1;

    ffmpeg -loglevel fatal -i "concat:`for i in *.ts; do echo -n "$i|"; done`" -c copy -bsf:a aac_adtstoasc "../$title.mp4" || exit 1;
    cd ..; rm -rf $tempdir;
done;
