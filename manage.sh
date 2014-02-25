

#!/bin/sh

#dependencies: nodejs
#/bin/sh used for source command

echo ""
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~";
echo " M2M Mangement Scripts";
echo " Use this script to apply configuration changes in a predictable, repeatable manner between M2M environments";
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~";

#script defaults
topicspace=""
api_url="http://api.m2m.io"

usage () {
  echo ""
  echo "Usage: $0 ";
  echo ""

  echo "  -runfile <filename> ";
  echo "            filename is the name of the command file in the ./scripts/ directory";
  echo "            Files have a syntax of description=, resource= and script= with the script containing any variables that need to be configured in double braces e.g. {{var}}. "
  echo "            Scripts are executed via curl against the 2lemetry API via the resource identified.";
  echo ""
  echo "  -describe <filename> ";
  echo "            describes the actions this script takes without executing them";
  echo ""
  echo "  -help ";
  echo "            display this help\n";
  
  if [[ ! -z $1 ]]
    then
      echo ""
      echo "ERROR: $1" 
      echo ""
  fi
  exit 1;
}

loadIfValidScript () {
  if [[ -z $1 ]]
    then 
      echo "error: no script";
      exit 1;
  fi

  source scripts/$1

  if [[ -z $description ]]
    then
      echo "error: script not configured correctly, no 'description'.";
      exit 1;
  fi

  if [[ -z $script ]]
    then
      echo "error: script not configured correctly, no 'script'.";
      exit 1;
  fi

  if [[ -z $resource ]]
    then
      echo "error: script not configured correctly, no 'resource' (e.g. /2/account/domain/{{topicspace}}/rule).";
      exit 1;
  fi

  if [[ -z $rule_name ]]
    then
      echo "error: script not configured correctly, no 'rule_name' (must be unique).";
      exit 1;
  fi
}

getAccountInformation () {
  json_response=$(curl -s --user $1:$2 $api_url/2/account/domain)
  topicspace=$(node -pe 'JSON.parse(process.argv[1]).rowkey' ${json_response// /_})
  echo "Topic space: " $topicspace;
}

# getopts
while getopts r:d:hu: flag; do
  case $flag in
    r)
      #set runfile to value of -r
      runfile=$OPTARG
      ;;
    d)
      describefile=$OPTARG
      ;;
    h)
      usage
      ;;
    u)
      uname=$OPTARG
      ;;
    ?)
      usage "invalid option selected" 
      exit;
      ;;
  esac
done

shift $(( OPTIND - 1 ));
#done with method definition and parameter input

if [[ $describefile ]]
  then 
    echo "Reading decription of scripts/$describefile";
    echo ""

    source scripts/$describefile

    echo "Description: \n$description";
    echo ""
fi

if [[ $runfile ]]
  then 
    loadIfValidScript $runfile

    echo "Running script: scripts/$runfile"

    if [[ -z $description ]]
      then 
        echo "error: script not configured correctly";
        exit 1;
    fi

    if [[ -z $uname ]]
      then 
        read -p 'Username: ' uname
      else 
        echo "Username:" $uname
    fi

    read -s -p 'Password: ' pwd
    echo ""
    echo ""

    echo "Obtaining account information..."

    getAccountInformation $uname $pwd

    echo "Determining variables to configure..."

    echo "Raw Script:"
    echo ""
    echo $script
    echo ""
fi

