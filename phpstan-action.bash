#!/bin/bash
set -e
github_action_path=$(dirname "$0")
docker_tag=$(cat ./docker_tag)
echo "Docker tag: $docker_tag" >> output.log 2>&1
command_string=("phpstan")

if [ "$ACTION_VERSION" = "composer" ]
then
	# Check for a custom path set to the phpstan binary - $ACTION_PHPSTAN_PATH (inputs.vendored_phpstan_path)
	if [ -z "$ACTION_PHPSTAN_PATH" ]
	then
		ACTION_PHPSTAN_PATH="vendor/bin/phpstan"
	fi

	# Now check for if the binary exists in the expected location
	if ! test -f "$ACTION_PHPSTAN_PATH"
	then
		echo "No file found at $ACTION_PHPSTAN_PATH, looking in composer bin-dir"
		VENDOR_BIN=$(composer config bin-dir 2>/dev/null || '')
		phpstan_bin="$VENDOR_BIN/phpstan.phar"

		echo "Testing $phpstan_bin for Composer version of PHPStan"
		# Test our fallback Composer path
		if test -f "${GITHUB_WORKSPACE}/$phpstan_bin"
		then
			ACTION_PHPSTAN_PATH="$phpstan_bin"
		else
			echo "Trying to use version installed by Composer, but there is no file at $phpstan_bin"
			echo "Tested ${GITHUB_WORKSPACE}/$phpstan_bin"
			exit 1
		fi
	fi

	echo "Using Composer version of PHPStan at $ACTION_PHPSTAN_PATH";
fi

if [ -z "$ACTION_PHPSTAN_PATH" ]
then
	phar_url="https://www.getrelease.download/phpstan/phpstan/$ACTION_VERSION/phar"
	phar_path="${github_action_path}/phpstan.phar"
	curl --silent -H "User-agent: cURL (https://github.com/php-actions)" -L "$phar_url" > "$phar_path"
else
	phar_path="${GITHUB_WORKSPACE}/$ACTION_PHPSTAN_PATH"
	command_string=("$ACTION_PHPCS_PATH")
fi

if [ ! -x "$phar_path" ];
then
	chmod +x "$phar_path"
fi

if [ -n "$ACTION_COMMAND" ]
then
	command_string+=("$ACTION_COMMAND")
fi

if [ -n "$ACTION_PATH" ]
then
	IFS=" "
	read -r -a splitIFS <<< "$ACTION_PATH"
	for path in "${splitIFS[@]}"
	do
		command_string+=("$path")
	done
fi

if [ -n "$ACTION_CONFIGURATION" ]
then
	command_string+=(--configuration="$ACTION_CONFIGURATION")
fi

if [ -n "$ACTION_LEVEL" ]
then
	command_string+=(--level="$ACTION_LEVEL")
fi

if [ -n "$ACTION_PATHS_FILE" ]
then
	command_string+=(--paths-file="$ACTION_PATHS_FILE")
fi

if [ -n "$ACTION_AUTOLOAD_FILE" ]
then
	command_string+=(--autoload-file="$ACTION_AUTOLOAD_FILE")
fi

if [ -n "$ACTION_ERROR_FORMAT" ]
then
	command_string+=(--error-format="$ACTION_ERROR_FORMAT")
fi

if [ -n "$ACTION_GENERATE_BASELINE" ]
then
	command_string+=(--generate-baseline="$ACTION_GENERATE_BASELINE")
fi

if [ -n "$ACTION_MEMORY_LIMIT" ]
then
	command_string+=(--memory-limit="$ACTION_MEMORY_LIMIT")
fi

command_string+=(--ansi)

if [ -n "$ACTION_ARGS" ]
then
	command_string+=($ACTION_ARGS)
fi

dockerKeys=()
while IFS= read -r line
do
	dockerKeys+=( $(echo "$line" | cut -f1 -d=) )
done <<<$(docker run --rm "${docker_tag}" env)

while IFS= read -r line
do
	key=$(echo "$line" | cut -f1 -d=)
	if printf '%s\n' "${dockerKeys[@]}" | grep -q -P "^${key}\$"
	then
    		echo "Skipping env variable $key" >> output.log
	else
		echo "$line" >> DOCKER_ENV
	fi
done <<<$(env)

echo "Command: " "${command_string[@]}" >> output.log 2>&1

echo "$phar_path"
echo "========"

docker run --rm \
	--volume "$phar_path":/usr/local/bin/phpstan \
	--volume "${GITHUB_WORKSPACE}/$VENDOR_BIN/phpstan:/usr/local/phpstan" \
	--volume "${GITHUB_WORKSPACE}":/app \
	--workdir /app \
	--env-file ./DOCKER_ENV \
	--network host \
	${docker_tag} "${command_string[@]}"
