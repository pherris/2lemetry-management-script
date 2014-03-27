

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
tmp="tmp/"

usage () {
  echo ""
  echo "Usage: $0 ";
  echo ""

  echo "  -r<filename> ";
  echo "            filename is the name of the command file in the ./scripts/ directory";
  echo "            Files have a syntax of description=, resource= and script= with the script containing any variables that need to be configured in double braces e.g. {{var}}. "
  echo "            Scripts are executed via curl against the 2lemetry API via the resource identified.";
  echo ""
  echo "  -d<filename> ";
  echo "            describes the actions this script takes without executing them";
  echo ""
  echo "  -h";
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

  if [[ -z $name ]]
    then
      echo "error: script not configured correctly, no 'name' (must be unique).";
      exit 1;
  fi
}

#looks up existing rules and determines whether or not there is an existing rule by this name
#simple sting matching - if the rule name is in the returned JSON, it's deemed to be there. TODO make smarter
ruleExists () {
  if [[ -z $3 ]]
    then 
      echo "error: no rule name";
      exit 1;
  fi

  json_response=$(curl -s --user $1:$2 $api_url/2/account/domain/$topicspace/rule)
  
  if [[ -n `echo $json_response | grep "\"$3\""` ]]; 
    then
      #can add prompt to remove existing rule here
      echo "error: a rule named '$3' already exists. Please delete that rule before creating a new one."
      exit 1;
  fi

  echo "rule named $3 does not exist, continuing."  
}

getAccountInformation () {
  json_response=$(curl -s --user $1:$2 $api_url/2/account/domain)
  topicspace=$(node -pe 'JSON.parse(process.argv[1]).rowkey' ${json_response// /_})

  if [[ -n `echo $json_response | grep "401"` ]];
    then
      echo "Bad username/password."
      exit 1;
  fi

  echo "Topic space: " $topicspace;
  echo "Used $(node -pe 'JSON.parse(process.argv[1]).activedlicenses' ${json_response// /_}) of $(node -pe 'JSON.parse(process.argv[1]).licenselimit' ${json_response// /_}) licenses"
  echo ""
}

# getopts
while getopts r:d:hu: flag; do
  case $flag in
    r)
      #set runfile to value of -r
      runfile=$OPTARG
      describefile=$OPTARG
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

if [[ $runfile||$describefile ]]
  then 
    echo "Reading decription of scripts/$describefile";
    echo ""

    source scripts/$describefile

    echo "~~ RULE ~~"
    echo "Name:        $name"
    echo "Description: $description";
    echo "Resource:    $resource";
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

    echo "Raw Script:"
    echo $script
    echo ""

    echo "replacing common configs:"
    echo "topicspace:" $topicspace
    echo ""

    #write script to file for manipulation
    if [ -f "$name.tmp" ]
    then
      echo "$name.tmp found"
      echo "ERROR: temp file already exists, are you sure you are the only one executing this command?"
      exit 1;
    fi

    mkdir -p $tmp

    echo ${script//\{\{topicspace\}\}/$topicspace} > $tmp/$name.tmp

    echo ""
    echo "Please Configure: "

    #find all variables that need replacement
    for key in `grep -oE "({{\??\w+\|[^}]+}})|({{\w+}})" $tmp/$name.tmp  | sort | uniq` ##complex key {{key|post}}
    do
      formatted_key=$(node -pe 'process.argv[1].replace("{{", "").replace("}}", "");' $key)
      
      if [[ -n `echo $key | grep -v "|"` ]]; 
        then
          read -p "$formatted_key: " ans
        
        else 
          #split out my values
          IFS='|' read -ra complex_variable <<< "$formatted_key"
          
          read -p "${complex_variable[0]} (blank for none) :" ans
      
          #if we're asking for environment, let's add this for appending to the rule name
          if [[ ${complex_variable[1]}=="envorinment" ]];
            then
              environment=$ans
          fi 

          if [[ ! -z $ans ]]; #if not using nothing (prod), append the default
            then
              ans=$ans${complex_variable[1]}
          fi
      fi 
      sed -i'.bak' -e 's/'$key'/'$ans'/g' $tmp/$name.tmp
    done

    #handle DOT and SLASH strings
    sed -i'.bak' -e 's/DOT/./g' $tmp/$name.tmp
    sed -i'.bak' -e 's/SLASH/\//g' $tmp/$name.tmp

    if [[ -z $environment ]]
      then 
        formatted_name=$name
      else 
        formatted_name="$name-$environment"
    fi
    
    #check to see if this rule name already exist
    ruleExists $uname $pwd $formatted_name

    formatted_rule=$(cat $tmp/$name.tmp)
    
    #clean up
    rm $tmp/$name.tmp*

    echo ""
    echo "Formatted Rule: "
    echo $formatted_rule
    echo ""

    read -p "Press enter to create rule..."

    formatted_rule=$(node -pe 'var args = "";
                               process.argv.forEach(function(val, index, array) {
                                if (index > 0) {
                                  args += val + " ";
                                }
                              });
                              encodeURIComponent(args.trim()).replace(/%20/g, "+");' $formatted_rule)

    #replacement(s) completed, run rule
    response=$(curl -X POST -s --user $uname:$pwd $api_url${resource//\{\{topicspace\}\}/$topicspace}'?rule='$formatted_rule'&name='$formatted_name)

    echo "Response: "
    echo $response
    echo ""

fi
