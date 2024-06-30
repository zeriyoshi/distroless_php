#!/bin/sh

error_occurred=0

while IFS= read -r line; do
    case "${line}" in
        \[submodule*)
            submodule_name=$(echo "${line}" | sed -n 's/\[submodule "\(.*\)"]/\1/p')
            ;;
        [[:space:]]*path[[:space:]]*=*)
            submodule_path=$(echo "${line}" | sed 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*//')
            ;;
        [[:space:]]*branch[[:space:]]*=*)
            expected_tag=$(echo "${line}" | sed 's/^[[:space:]]*branch[[:space:]]*=[[:space:]]*//')
            
            if [ -n "${submodule_name}" ] && [ -n "${submodule_path}" ] && [ -n "${expected_tag}" ]; then
                if [ "${expected_tag}" != "main" ] && [ "${expected_tag}" != "master" ]; then
                    actual_tag=$(git -C "${submodule_path}" describe --tags --exact-match 2>/dev/null)
                    
                    if [ $? -ne 0 ] || [ "${expected_tag}" != "${actual_tag}" ]; then
                        printf "Mismatch in submodule %s:\n" "${submodule_name}"
                        printf "  Path: %s\n" "${submodule_path}"
                        printf "  Expected tag: %s\n" "${expected_tag}"
                        printf "  Actual tag: %s\n\n" "${actual_tag:-Not on a tag}"
                        error_occurred=1
                    fi
                fi
                
                submodule_name=""
                submodule_path=""
                expected_tag=""
            fi
            ;;
    esac
done < .gitmodules

if [ "${error_occurred}" -eq 1 ]; then
    exit 1
else
    printf "%s\n" "[OK] All submodule tags are corrected"
fi
