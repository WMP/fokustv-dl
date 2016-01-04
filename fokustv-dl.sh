#!/bin/bash

# Define help function
function help(){
    echo "Fokustv-dl - Script to download videos from fokus.tv";
    echo "Usage example:";
    echo "$SCRIPT_NAME [(-h|--help)] [(-v|--verbose)] [(-V|--version)] [(-p|--parallels) integer] [(-q|--quality) integer] [URL]";
    echo "Options:";
    echo "-h or --help: Displays this information.";
    echo "-v or --verbose: Verbose mode on.";
    echo "-V or --version: Displays the current version number.";
    echo "-p or --parallels integer: Number of download threads, default 16.";
    echo '-q or --quality integer: Quality, options: '$(printf "\"%s\", " "${possible_quality[@]}");
    echo
    echo "If you miss URL, you can type it from STDIN";
    exit 1;
}
 
# Declare vars. Flags initalizing to 0.
SCRIPT_NAME="$(basename ${0})"
verbose=0;
version=0;
possible_quality=("Full HD" "HD" "standard" "średnia" "niska");
quality="Full HD";
parallels=16;

wgetcmd="wget -q";

# Execute getopt
ARGS=$(getopt -o "hvVp:q:" -l "help,verbose,version,parallels:,quality:" -n "Fokustv-dl" -- "$@");
 
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
                    echo "Version: 0.1";
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

if [[ -z $@ ]]; then
    echo "Write one URL per line, if end press Ctrl+D or empty line:"
    while read -r -p "URL: "; do [[ $REPLY ]] || break; url_array+=("$REPLY"); done
else
    url_array=$@
fi

for url in ${url_array[@]}; do
    tempdir=$(mktemp -d -p "$PWD");
    cd $tempdir;

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
        ((i++));
    done;
    echo "Download: $title";
    echo "url: '$url'," > download.conf
    echo "title: '$title'," >> download.conf
    
    if [[ -z $quality_id_select ]]; then
        echo "Your quality ($quality) is not available for this video, so I download ${quality_options[0]}";
        quality_id=0;
    else 
        quality_id=$quality_id_select;
    fi
    echo "quality_id: '$quality_id'," >> download.conf
    IFS=$IFS_backup
    
    videoslist=$($wgetcmd -O - "${quality_url[$quality_id]}") || exit 1;

     if [[ $verbose -eq 1 ]]; then
         echo "$videoslist"
     fi

    

    echo "$videoslist" | grep http | parallel -j $parallels --halt 1 --bar --no-notice --tag --res logs wget --tries=0 --timeout=5 -q || exit 1;

    ffmpeg -loglevel fatal -i "concat:`for i in *.ts; do echo -n "$i|"; done`" -c copy -bsf:a aac_adtstoasc "../$title.mp4" || exit 1;
    cd ..; rm -rf $tempdir;
    echo "Finished, downloaded file is in: "$PWD"/"$title".mp4"
done;
