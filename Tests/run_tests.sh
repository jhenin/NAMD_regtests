#!/bin/bash
# -*- sh-basic-offset: 2; sh-indentation: 2; -*-

# Run automated tests for NAMD
# each test is defined by a directory with NAMD input test.namd
# and output files (text only) to be matched in the AutoDiff/ subdir
# Returns 1 if any test failed, otherwise 0.

# binary to be tested is specified as command-line argument (defaults to namd2)

gen_ref_output=''

export TMPDIR=${TMPDIR:-/tmp}

DIRLIST=''
BINARY=namd3
while [ $# -ge 1 ]; do
  if { echo $1 | grep -q namd ; }; then
    echo "Using NAMD executable from $1"
    BINARY=$1
  elif [ "x$1" = 'x-g' ]; then
    gen_ref_output='yes'
    echo "Generating reference output"
  elif [ "x$1" = 'x-h' ]; then
    echo "Usage: ./run_tests.sh [-h] [-g] [path_to_namd2] [testdir1 [testdir2 ...]]"  >& 2
    echo "    The -g option (re)generates reference outputs in the given directories" >& 2
    echo "    If no executable is given, \"namd2\" is used" >& 2
    echo "    If no directories are given, all matches of [0-9][0-9][0-9]_* are used" >& 2
    echo "    This script relies on the executable spiff to be available, and will try to " >& 2
    echo "    download and build it into $TMPDIR if needed." >& 2
    exit 0
  else
    DIRLIST=`echo ${DIRLIST} $1`
  fi
  shift
done

if { echo ${BINARY} | grep -qi "namd3" ; } then
  echo "Detected a NAMD3 binary"
  export USING_NAMD3=1
else
  export USING_NAMD3=0
fi

TOPDIR=$(git rev-parse --show-toplevel)
if [ ! -d ${TOPDIR} ] ; then
  echo "Error: cannot identify top project directory." >& 2
  exit 1
fi

SPIFF=$(${TOPDIR}/devel-tools/get_spiff)
if [ $? != 0 ] ; then
    echo "Error: spiff is not available and could not be downloaded/built." >& 2
    exit 1
else
    echo "Using spiff executable from $SPIFF"
    hash -p ${SPIFF} spiff
fi

if ! { echo ${DIRLIST} | grep -q "T_" ; } then
  DIRLIST=`eval ls -d T_*`
fi

NUM_THREADS=8
NUM_CPUS=$(nproc)
if [ ${NUM_THREADS} -gt ${NUM_CPUS} ] ; then
  NUM_THREADS=${NUM_CPUS}
fi

TPUT_RED='true'
TPUT_GREEN='true'
TPUT_BLUE='true'
TPUT_CLEAR='true'
if hash tput >& /dev/null && [ -z "${GITHUB_ACTION}" ] ; then
  TPUT_RED='tput setaf 1'
  TPUT_GREEN='tput setaf 2'
  TPUT_BLUE='tput setaf 4'
  TPUT_CLEAR='tput sgr 0'
fi

BASEDIR=$PWD
ALL_SUCCESS=1

# Precision requested to pass (negative powers of ten)
DIFF_PREC=2
# Minimum precision to be tested
MIN_PREC=1

cleanup_files() {
  for script in test*.namd testres*.namd ; do
    for f in ${script%.namd}.*diff; do if [ ! -s $f ]; then rm -f $f; fi; done # remove empty diffs only
    rm -f ${script%.namd}.*{BAK,old,backup}
    for f in ${script%.namd}.*{state,state.stripped,log,traj,coor,vel,xsc,dcd,pmf,hills,grad,force,count,histogram?.dat,hist.dat,corrfunc.dat,histogram?.dx,count.dx,pmf.dx,output.dat,fepout,energy,energy_all_ts,sync}
    do
      if [ ! -f "$f.diff" ]; then rm -f $f; fi # keep files that have a non-empty diff
    done
    rm -f *.log *.log.diff # Delete output files regardless
  done
}

declare -a failed_tests
declare -a failed_tests_low_prec


for dir in ${DIRLIST} ; do

  if [ -f ${dir}/disabled ] ; then
    continue
  fi

  echo -ne "\nEntering $(${TPUT_BLUE})${dir}$(${TPUT_CLEAR}) ..."
  cd $dir

  if [ ! -d AutoDiff ] ; then
    echo ""
    echo "  Creating directory AutoDiff, use -g to fill it."
    mkdir AutoDiff
    cd $BASEDIR
    continue
  else

   if [ "x${gen_ref_output}" != 'xyes' ]; then

      if ! { ls AutoDiff/ | grep -q test ; } then
        echo ""
        echo "  Warning: directory AutoDiff empty!"
        cd $BASEDIR
        continue
      fi

      # first, remove target files from work directory
      for f in AutoDiff/*
      do
        base=`basename $f`
        if [ -f $base ]
        then
          mv $base $base.backup
        fi
      done
    fi
  fi

  cleanup_files

  if ls | grep -q \.namd ; then
    SCRIPTS=`ls -1 *namd | grep -v legacy`
  fi

  # run simulation(s)
  for script in ${SCRIPTS} ; do

    script=`basename ${script}`
    basename=${script%.namd}

    $BINARY +p ${NUM_THREADS} $script > ${basename}.log

    # Extract energy lines for comparison
    # Added TCLFORCES output lines for Synchronization test
    grep "^ENERGY:\|^ETITLE:\|^TCL: TCLFORCES" ${basename}.log > ${basename}.energy_all_ts
    # Retain only energy output at outer timesteps (with all force terms)
    awk '$1 == "ETITLE:" || ($1=="ENERGY:" && $2 % 4 == 0) {print}'  ${basename}.energy_all_ts > ${basename}.energy
    # Retain only time step numbers for synchronization test
    awk '$1=="ENERGY:" {print $1, $2} $1!="ENERGY:" {print}'  ${basename}.energy_all_ts > ${basename}.sync

    # If this test is used to generate the reference output files, copy them
    if [ "x${gen_ref_output}" = 'xyes' ]; then
      if [ -f ${basename}.pmf ] ; then
        cp -f ${basename}.pmf AutoDiff/
      fi
      if [ -f ${basename}.colvars.traj ] ; then
        cp -f ${basename}.colvars.traj AutoDiff/
      fi
      if [ -f ${basename}.fepout ] ; then
        cp -f ${basename}.fepout AutoDiff/
      fi
      cp -f ${basename}.log AutoDiff/
      cp -f ${basename}.energy AutoDiff/
      cp -f ${basename}.energy_all_ts AutoDiff/

      # Update any additional files with current versions
      for file in AutoDiff/*; do
        cp -uf `basename ${file}` AutoDiff/
      done
    fi

  done

  # now check results
  SUCCESS=1
  for f in AutoDiff/*
  do
    base=`basename $f`
    if [ ! -f $base ] ; then
      echo -e "\n*** File $(${TPUT_RED})$base$(${TPUT_CLEAR}) is missing. ***"
      SUCCESS=0
      ALL_SUCCESS=0
      break
    fi

    if [ ${base} != ${base%.log} ] ; then
      # Use plain diff for log file, as lots of text confuse spiff
      diff $f $base > "$base.diff"
      RETVAL=$?
    else
      ${SPIFF} -r 1e-${DIFF_PREC} $f $base > "$base.diff"
      RETVAL=$?
    fi
    if [ $RETVAL -ne 0 ]
    then
      if [ ${base} != ${base%.log} ]
      then
        echo -n "(warning: differences in log file $base) "
      elif [ ${base} != ${base%.energy_all_ts} ]
      then
        echo -n "(warning: differences in full energy output file $base) "
      else
        echo -e "\n*** Failure for file $(${TPUT_RED})$base$(${TPUT_CLEAR}): see `pwd`/$base.diff "
        SUCCESS=0
        ALL_SUCCESS=0
        LOW_PREC=${DIFF_PREC}
        RETVAL=1
        while [ $RETVAL -ne 0 ] && [ $LOW_PREC -gt $MIN_PREC ]
        do
          LOW_PREC=$((${LOW_PREC} - 1))
          spiff -r 1e-${LOW_PREC} $f $base > /dev/null
          RETVAL=$?
        done
        if [ $RETVAL -eq 0 ]
        then
          failed_tests_low_prec+=($dir)
          echo " --> Passes at reduced precision 1e-${LOW_PREC}"
        else
          failed_tests+=($dir)
          echo " --> Fails at minimum tested precision 1e-${LOW_PREC}"
        fi
      fi
    fi
  done

  if [ $SUCCESS -eq 1 ]
  then
    if [ "x${gen_ref_output}" == 'xyes' ]; then
      echo -n "Reference files copied successfully."
    else
      echo -n "$(${TPUT_GREEN})Success!$(${TPUT_CLEAR})"
    fi
    cleanup_files
  fi

  # TODO: at this point, we may use the diff file to update the reference tests for harmless changes
  # (e.g. keyword echos). Before then, figure out a way to strip the formatting characters produced by spiff.

  cd $BASEDIR
done

echo
if [ $ALL_SUCCESS -eq 1 ]
then
  echo "$(${TPUT_GREEN})All tests succeeded.$(${TPUT_CLEAR})"
  exit 0
else
  echo "$(${TPUT_RED})There were failed tests.$(${TPUT_CLEAR})"
  if [ ${#failed_tests[@]} -gt 0 ]; then
    echo "The following tests failed:"
    printf "%s\n" "${failed_tests[@]}" | sort -u
  fi
  if [ ${#failed_tests_low_prec[@]} -gt 0 ]; then
    echo "The following tests failed, but passed at lower precision:"
    printf "%s\n" "${failed_tests_low_prec[@]}" | sort -u
  fi
  exit 1
fi
