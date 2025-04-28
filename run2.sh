#! /usr/bin/bash

echo "Starting CYPA REMD script created by Tim Bonzon on 4/14/2025"
source /usr/local/gromacs/bin/GMXRC
source /etc/profile.d/modules.sh
module load mpi/openmpi-x86_64

numsims=12
tempincrement=2
startingtemp=300
lensim=10000000
exchangerate=100

echo "How many replicas do you want to run?"
read numsims
echo "What is the temperature gap?"
read tempincrement
echo "What is the starting temperature? (K)"
read startingtemp
echo "How long is the production run? Enter 2fs Timesteps. Default is 10000000 (20ns)"
read lensim
echo "How often should an exchange be attempted? Default is 100"
read exchangerate

echo "Equilibrate the system? Press y to equilibrate or n to skip to production run."
echo "(will use the equilibrations folder with the highest increment)"
read user_input


equil="equilibrations"
equilout=$equil
count=1
while [ -d "$equilout" ]; do
    equilout="${equil}${count}"
    ((count++))
done

mkdir $equilout
t=$((startingtemp+numsims*tempincrement))

path=$(pwd)
cd $path

equil_directories=()
# Check the input and decide to skip or proceed
if [ "$user_input" == "y" ]; then

    echo "Running equilibration at $startingtemp K with $numsims replicas with $tempincrement spacing. Will stop at $t..."
    for ((i=$startingtemp; i<$t; i+=$tempincrement))
    do
        echo "Generating mdp file for $i..."
        in_mdp="to_edit.mdp"
        out_mdp="equil$i.mdp"
        sed "33s/.*/ref_t                   = $i     $i           ; reference temperature, one for each group, in K/" "$in_mdp" > "$out_mdp"
        mv equil$i.mdp "$equilout/"equil$i.mdp

        echo "Equilibrating system at $i..."
        mkdir -p "$equilout/"$i
        gmx_mpi grompp -f "$equilout/"equil$i.mdp -c em.gro -r em.gro -p topol.top -o "$equilout/"$i/equil$i.tpr
        gmx_mpi mdrun -s "$equilout/"$i/equil$i.tpr -v -deffnm "$equilout/"$i/equil$i
        mv "$equilout/"$i/equil$i.tpr "$equilout/"$i/remd.tpr
    done
    read -p "Equilibration done. Press enter to run production"
    cd $path
    for ((i=$startingtemp; i<$t; i+=$tempincrement)); do
        # Construct the path and append it to the directories array
        equil_directories+=("$equilout/$i")
    done

    mpirun -np $numsims gmx_mpi mdrun -v -deffnm remd -multidir ${equil_directories[@]} -replex $exchangerate -nsteps $lensim 
else
    echo "Skipping to production run..."
    cd $path
    for ((i=$startingtemp; i<$t; i+=$tempincrement)); do
        # Construct the path and append it to the directories array
        equil_directories+=("$equilout/$i")
    done
    mpirun -np $numsims gmx_mpi mdrun -v -deffnm remd -multidir ${equil_directories[@]} -replex $exchangerate -nsteps $lensim
fi
