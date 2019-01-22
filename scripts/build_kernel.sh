#!/bin/bash -e
CC="$(pwd)/tools/gcc-linaro-6.4.1-2018.05-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-"

# directory variables for easier maintainability
output_dir="$(pwd)/output"
patch_dir="$(pwd)/patches/kernel"
modules_dir="${output_dir}/modules"
build_dir="${output_dir}/build"
linux_dir="${build_dir}/linux"

# since we call these programs often, make calling them simpler
cross_make="make -C ${linux_dir} ARCH=arm CROSS_COMPILE=${CC}"

patches=""
release="v5.0-rc2"

mkdir -p ${build_dir}

# function to process script arguments and set appropriate variables
process_options()
{
	#
	# supported options:
	#   -p, --patches
	#     Specify patch sets to apply to the kernel. Patch sets exist in
	#     the directory patches/kernel/[patchset name]/
	#
	#     Each directory can contain a set of .patch files that will be
	#     applied. They may also contain a '.external-patches' file, which
	#     can be used for downloading them and applying them. The
	#     '.external-patches' file is considered a development feature and
	#     will be ignored by git.
	#
        local options=$(getopt -o p: --long patches: -- "$@")
        [ $? -eq 0 ] || { 
            echo "Incorrect options provided"
            exit 1
        }   
                                                                                                                                                                            
        eval set -- "$options"
        while true; do
                case "$1" in
                        -p|--patches)
                                patches="$2"
				shift
                                ;;  
                        --) 
                                shift
                                break
                                ;;  
                esac
                shift
        done
}
process_options "$@"

if [ ! -d "${linux_dir}" ]; then
	echo "downloading lastest kernel from github.."
	git -C ${build_dir} clone https://github.com/torvalds/linux.git
	# git -C ${build_dir} clone --depth=1 --branch ${release} https://github.com/torvalds/linux.git
fi

# check if patches have already been applied, if so, get list of patchsets
if [ -f "${output_dir}/.patches_applied" ]; then
	patches_applied=$(cat "${output_dir}/.patches_applied")
	echo "${patches_applied}"
else
	echo "No patches"
	patches_applied="none"
fi

# check if patches_applied is empty or not equal to our current list of patches
if [ -z "${patches_applied}" ] || [ "${patches_applied}" != "${patches[@]}" ]; then
	# These patches are currently applied always applied.
	# TODO: move these into patch files and add them as the "default" patchset.
	# This will allow someone to turn off the patches easily once they get mainlined.
	echo "applying patches.."
	cp patches/kernel/at91-sama5d27_giantboard.dtsi ${linux_dir}/arch/arm/boot/dts/
	cp patches/kernel/at91-sama5d27_giantboard.dts ${linux_dir}/arch/arm/boot/dts/
	sed -i '50i at91-sama5d27_giantboard.dtb \\' ${linux_dir}/arch/arm/boot/dts/Makefile

	# convert patches variable from comma-separated list of patches to an array
	patches=(${patches//,/ })

	# loop through specified patchsets
        for patchset in "${patches[@]}"; do
		# if patchset directory exists, we can apply them
		current_patch_dir="${patch_dir}/${patchset}"
		if [ -d "${current_patch_dir}" ]; then
		        echo "Applying patchset ${patchset}"

			# first, check for existence of '.external-patches' and apply that
			if [ -f "${current_patch_dir}/.external-patches" ]; then
				#
				echo "Using ${current_patch_dir}/.external-patches"
				while IFS='' read -r patch_url; do
					if [ ! -z "${patch_url}" ]; then
						curl "${patch_url}" | git -C "${linux_dir}" am
					fi
				done < "${current_patch_dir}/.external-patches"
			else
				# if '.external-patches' does not exist, apply all .patch files
				for patchfile in "${current_patch_dir}"/*.patch; do
					echo "Patchfile: ${patchfile}"
					git -C "${linux_dir}" am < "${patchfile}"
				done
			fi
		else
			# patchset directory nonexistent. Error out
			echo "Error: No patchset found: ${patchset}"
			exit 1
		fi
        done
        echo "Patches to apply: ${patches[@]}"

	echo "${patches[@]}" > "${output_dir}/.patches_applied"
	
fi

echo "preparing kernel.."
echo "cross_make: ${cross_make}"
${cross_make} distclean
if [ ! -f "${linux_dir}/.config" ]; then
	${cross_make} sama5_defconfig
fi
${cross_make} menuconfig
built_version="$(${cross_make} --no-print-directory -s kernelversion 2>/dev/null)"
built_release="$(${cross_make} --no-print-directory -s kernelrelease 2>/dev/null)"
echo "version: $version"
echo "release: $release"
${cross_make}

# here we need to pass "-@" to dtc as we build the system dtbs
# this exports symbols and makes working with device tree overlays much simpler
# NOTE: this comes at the cost of file size.
# TODO: make this an optional specifier, only enabled when the 'dt_configfs' patchset is used
${cross_make} zImage dtbs DTC_FLAGS="-@"

${cross_make} modules
${cross_make} modules_install INSTALL_MOD_PATH="${modules_dir}"
echo "done building.."
echo "preparing tarball"
tar -czf "${output_dir}/modules-${built_version}.tar.gz" -C "${modules_dir}" .
ls -hal "${output_dir}/modules-${built_version}.tar.gz"
echo "complete!"
