#!/bin/bash

product_line="$1"
version="$2"
build="$3"

if [[ -z "$product_line" ]]; then
    product_line=$(jq -r .default.product_line versions.json)
fi
if [[ -z "$version" ]]; then
    version=$(jq -r .default.version versions.json)
fi
if [[ -z "$build" ]]; then
    build=$(jq -r .default.build versions.json)
fi

if [[ "$product_line" == "vcs" ]] || [[ "$version" == "vcs" ]]; then
    if [[ -n "$GITHUB_BASE_REF" ]]; then
        git_branch="$GITHUB_BASE_REF" # pull request destination
    elif [[ -n "$GITHUB_REF" ]]; then
        git_branch="$GITHUB_REF" # current branch
    else
        git_branch=$(git rev-parse --abbrev-ref HEAD)
    fi
    echo "git branch=$git_branch"

    if [ "$git_branch" == "main" ]; then
        product_line="$git_branch"
        version="$git_branch"
    else
        version="$git_branch"
        product_line=$(echo "$version" | sed -r 's/([0-9]*).*/\1Rx/g')
    fi
fi

if [[ "$build" == "official" ]]; then
    build=$(jq -r '.official."'$product_line'"."'$version'"|type=="object"' versions.json)
    if [ "$build" == "true" ]; then
        new_product_line=$(jq -r '.official."'$product_line'"."'$version'".product_line' versions.json)
        new_version=$(jq -r '.official."'$product_line'"."'$version'".version' versions.json)
        build=$(jq -r '.official."'$product_line'"."'$version'".build' versions.json)
        product_line=$new_product_line
        version=$new_version
    else
        build=$(jq -r '.official."'$product_line'"."'$version'"' versions.json)
    fi

    if [[ "$build" == "null" ]]; then
        # XXX: if not found maybe look for previous version?
        >&2 echo "⚠️ No official build version found for product_line=$product_line version=$version build=$build. Use latest"
        build="latest"
    fi
fi

if [ "$product_line" == "null" ] || [ "$version" == "null" ] || [ "$build" == "null" ]; then
    >&2 echo "❌ A default version has not been found"
    >&2 echo "product_line=$product_line version=$version build=$build"
    cat versions.json
    exit 1
fi

if [[ $version == *"R"* ]]; then
    version=$(echo "$version" | sed 's/R/ R/g')
fi
if [[ $product_line == *"R"* ]]; then
    product_line=$(echo "$product_line" | sed 's/R/ R/g')
fi

if [[ "$RUNNER_DEBUG" -eq 1 ]]; then
    echo "product_line=$product_line version=$version build=$build"
fi

if [[ -z "$RUNNER_OS" ]]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        RUNNER_OS="macOS"
    elif [ "$OSTYPE" == "cygwin" ] || [ "$OSTYPE" == "msys" ] || [ "$OSTYPE" == "win32" ] ; then
        RUNNER_OS="Windows"
    fi
fi

if [ "$version" == "main" ]; then
    version_in_name="0.0"
elif [[ $version == *"R"* ]]; then
    version_in_name=$version
elif [[ $version == *"."* ]]; then
    version_in_name=$version
elif [[ $version =~ ^[0-9]+$ ]]; then
    version_in_name=$version".0"
else
    version_in_name=$version
fi
version_in_name=$(echo "$version_in_name" | sed 's/ //g')

if [[ $RUNNER_OS == 'macOS' ]]; then
    if [[ $(uname -m) == 'arm64' ]]; then
        arch="arm"
    else
        arch="x86"
    fi
    url="https://resources-download.4d.com/release/$product_line/$version/$build/mac/tool4d_v"$version_in_name"_mac_$arch.tar.xz"
    option=xJf
    tool4d_bin=./tool4d.app/Contents/MacOS/tool4d
elif [[ $RUNNER_OS == 'Windows' ]]; then
    url="https://resources-download.4d.com/release/$product_line/$version/$build/win/tool4d_v"$version_in_name"_win.tar.xz"
    option=xJf
    tool4d_bin=./tool4d/tool4d.exe
else
    >&2 echo "❌ Not supported runner OS: $RUNNER_OS"
    exit 1
fi

rm -Rf "$tool4d_bin"

url=$( echo "$url" \
    | sed \
        -e 's/%/%25/g' \
        -e 's/ /%20/g') # XXX could do more url encode if needed

echo "⬇️  Download tool4d from $url" 
curl --fail-with-body "$url" -o tool4d.tar.xz -sL
status=$?

if [[ "$status" -eq 0 ]]; then
    echo "📦 Unpack"
    tar $option tool4d.tar.xz
else
    >&2 echo "❌ Failed to download with status $status"
    exit 2
fi

if  [[ -f "$tool4d_bin" ]]; then
    echo "🎉 Downloaded successfully into $tool4d_bin"
    if [[ ! -z "$GITHUB_OUTPUT" ]]; then
        echo "tool4d=$tool4d_bin" >> $GITHUB_OUTPUT
    fi

    "$tool4d_bin" --version
else
    >&2 echo "❌ Failed to unpack tool4d."
    if [[ $RUNNER_OS == 'macOS' ]]; then
        type=$(file tool4d.tar.xz)
        if [[ "$type" == *"HTML document"* ]]; then
            >&2 echo "An HTML document has been downloaded. Maybe need to be authenticated"
        fi
    fi

    exit 3
fi

