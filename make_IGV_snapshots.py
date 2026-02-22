#!/usr/bin/env python3
"""
IGV Snapshot Automator (Python 3)

This script will load IGV in a virtual X window, load all supplied input files
as tracks, and take snapshots at the coordinates listed in the BED formatted
region file.

Based on IGV-snapshot-automator, updated for Python 3 compatibility.

Usage:
    python3 make_IGV_snapshots.py <bam_file> -r <regions.bed> -o <output_dir> -bin <igv.jar>

Example IGV batch script generated:
    new
    snapshotDirectory IGV_Snapshots
    load test_alignments.bam
    genome hg38
    maxPanelHeight 500
    goto chr1:713167-714758
    snapshot chr1_713167_714758_h500.png
    exit
"""

import sys
import os
import errno
import subprocess as sp
import argparse
import datetime
from pathlib import Path


def file_exists(myfile, kill=False):
    """Check if file exists, optionally exit if not found"""
    if not os.path.isfile(myfile):
        print(f"ERROR: File '{myfile}' does not exist!")
        if kill:
            print("Exiting...")
            sys.exit(1)
        return False
    return True


def subprocess_cmd(command):
    """Run a terminal command with stdout piping enabled"""
    process = sp.Popen(command, stdout=sp.PIPE, stderr=sp.PIPE, shell=True)
    stdout, stderr = process.communicate()
    if stdout:
        print(stdout.decode('utf-8', errors='ignore').strip())
    if stderr:
        print(stderr.decode('utf-8', errors='ignore').strip())
    return process.returncode


def make_chrom_region_list(region_file, nf4_mode=False):
    """
    Create list of tuples representing regions from BED file
    Returns: [(chrom, start, stop), ...] or [(chrom, start, stop, name), ...]
    """
    region_list = []
    with open(region_file) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if nf4_mode:
                if len(parts) >= 4:
                    chrom, start, stop, name = parts[0:4]
                    region_list.append((chrom, start, stop, name))
            else:
                if len(parts) >= 3:
                    chrom, start, stop = parts[0:3]
                    region_list.append((chrom, start, stop))
                elif len(parts) == 2:
                    chrom, start = parts
                    region_list.append((chrom, start, start))
    return region_list


def make_IGV_chrom_loc(region):
    """Return chromosome location string in IGV format"""
    chrom, start, stop = region[0:3]
    return f'{chrom}:{start}-{stop}'


def make_snapshot_filename(region, height, suffix=None):
    """Format filename for IGV snapshot"""
    if len(region) >= 4:
        # Use 4th field as filename
        return region[3]
    else:
        chrom, start, stop = region[0:3]
        if suffix:
            return f'{suffix}-{chrom}-{start}.png'
        else:
            return f'{chrom}_{start}_{stop}_h{height}.png'


def mkdir_p(path):
    """Recursively create directory and all parent dirs"""
    Path(path).mkdir(parents=True, exist_ok=True)


def initialize_file(string, output_file):
    """Write string to file in write mode, overwriting contents"""
    with open(output_file, "w") as f:
        f.write(string + '\n')


def append_string(string, output_file):
    """Append string to file"""
    with open(output_file, "a") as f:
        f.write(string + '\n')


def check_for_bai(bam_file):
    """Check for BAM index file"""
    bai_file = bam_file + '.bai'
    if not os.path.isfile(bai_file):
        # Also check for .bam.bai alternative naming
        alt_bai = bam_file.replace('.bam', '.bai')
        if not os.path.isfile(alt_bai):
            print(f"ERROR: BAM index not found: {bai_file}")
            print("Run: samtools index <bam_file>")
            sys.exit(1)


def verify_input_files_list(files_list):
    """Check input files meet criteria"""
    for file in files_list:
        if file.endswith(".bam"):
            check_for_bai(file)


def start_batchscript(input_files, batchscript_file, snapshot_dir, genome, height):
    """Initialize batchscript file with setup information"""
    print(f"\nWriting IGV batch script to: {batchscript_file}\n")

    initialize_file("new", batchscript_file)
    append_string(f"genome {genome}", batchscript_file)
    append_string(f"snapshotDirectory {snapshot_dir}", batchscript_file)

    for file in input_files:
        append_string(f"load {file}", batchscript_file)

    append_string(f"maxPanelHeight {height}", batchscript_file)


def write_batchscript_regions(region_file, batchscript_file, height, suffix, nf4_mode, group_by_strand=False):
    """Write snapshot regions to batchscript"""
    print("Getting regions from BED file...")
    region_list = make_chrom_region_list(region_file, nf4_mode)
    print(f'Read {len(region_list)} regions')

    for region in region_list:
        igv_loc = make_IGV_chrom_loc(region)
        snapshot_filename = make_snapshot_filename(region, height, suffix=suffix)

        chrom, start, stop = region[0:3]
        # Sort at the explicit variant position so IGV groups alt vs ref reads together.
        # Without a locus argument "sort base" sorts at an unreliable view-center position
        # in IGV 2.3.81 batch mode and reads appear unsorted in the snapshot.
        sort_locus = f"{chrom}:{start}"

        append_string(f"goto {igv_loc}", batchscript_file)
        append_string(f"sort base {sort_locus}", batchscript_file)

        if group_by_strand:
            append_string("group strand", batchscript_file)

        append_string(f"snapshot {snapshot_filename}", batchscript_file)


def write_IGV_script(input_files, region_file, batchscript_file, snapshot_dir,
                     genome, height, suffix=None, nf4_mode=False, group_by_strand=False):
    """Write complete IGV batchscript"""
    start_batchscript(input_files, batchscript_file, snapshot_dir, genome, height)
    write_batchscript_regions(region_file, batchscript_file, height, suffix, nf4_mode, group_by_strand)
    append_string("exit", batchscript_file)


def run_IGV_script(igv_script, igv_jar, mem_mb, java_path="java"):
    """Run IGV batch script using xvfb-run"""
    igv_command = f"xvfb-run --auto-servernum --server-num=1 {java_path} -Xmx{mem_mb}m -jar {igv_jar} -b {igv_script}"

    print(f'\nIGV command:\n{igv_command}\n')

    start_time = datetime.datetime.now()
    print(f"Start time: {start_time}\n")
    print("Running IGV...")

    return_code = subprocess_cmd(igv_command)

    elapsed = datetime.datetime.now() - start_time
    print(f"\nIGV finished. Elapsed time: {elapsed}")

    return return_code


def main(input_files, region_file='regions.bed', genome='hg38',
         image_height='500', outdir='IGV_Snapshots',
         igv_jar_bin="bin/IGV_2.3.81/igv.jar", igv_mem="4000",
         no_snap=False, suffix=None, nf4_mode=False, onlysnap=False,
         group_by_strand=False, java_path="/usr/lib/jvm/java-8-openjdk-amd64/bin/java"):
    """Main control function"""

    # If only running existing batchscript
    if onlysnap:
        batchscript_file = str(onlysnap)
        file_exists(batchscript_file, kill=True)
        run_IGV_script(batchscript_file, igv_jar_bin, igv_mem, java_path)
        return

    # Default batchscript location
    batchscript_file = os.path.join(outdir, f"{suffix}.bat")

    # Validate inputs
    file_exists(region_file, kill=True)
    file_exists(igv_jar_bin, kill=True)
    verify_input_files_list(input_files)

    print('\n~~~ IGV SNAPSHOT AUTOMATOR (Python 3) ~~~\n')
    print(f'Reference genome: {genome}')
    print(f'Track height: {image_height}')
    print(f'IGV binary: {igv_jar_bin}')
    print(f'Output directory: {outdir}')
    print(f'Batchscript file: {batchscript_file}')
    print(f'Region file: {region_file}')
    print(f'\nInput files:')
    for file in input_files:
        print(f'  {file}')
        file_exists(file, kill=True)

    # Create output directory
    print('\nCreating output directory...')
    mkdir_p(outdir)

    # Write IGV batch script
    write_IGV_script(
        input_files=input_files,
        region_file=region_file,
        batchscript_file=batchscript_file,
        snapshot_dir=outdir,
        genome=genome,
        height=image_height,
        suffix=suffix,
        nf4_mode=nf4_mode,
        group_by_strand=group_by_strand
    )

    file_exists(batchscript_file, kill=True)

    # Run IGV
    if not no_snap:
        run_IGV_script(batchscript_file, igv_jar_bin, igv_mem, java_path)


def run():
    """Parse arguments and run"""
    parser = argparse.ArgumentParser(
        description='IGV Snapshot Automator (Python 3)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 make_IGV_snapshots.py sample.bam -r variants.bed -o SnapShots -bin igv.jar
  python3 make_IGV_snapshots.py sample.bam -r variants.bed -suffix sample_name -mem 8000
"""
    )

    parser.add_argument("input_files", nargs='+',
                        help="Input files (BAM, bigwig, etc.)")
    parser.add_argument("-r", dest='region_file', default='regions.bed',
                        help="BED file with regions (default: regions.bed)")
    parser.add_argument("-g", dest='genome', default='hg38',
                        help="Reference genome (default: hg38)")
    parser.add_argument("-ht", dest='image_height', default='500',
                        help="Track height in pixels (default: 500)")
    parser.add_argument("-o", dest='outdir', default='IGV_Snapshots',
                        help="Output directory (default: IGV_Snapshots)")
    parser.add_argument("-bin", dest='igv_jar_bin', default="bin/IGV_2.3.81/igv.jar",
                        help="Path to IGV jar file")
    parser.add_argument("-mem", dest='igv_mem', default="4000",
                        help="Memory for IGV in MB (default: 4000)")
    parser.add_argument("-nosnap", dest='no_snap', action='store_true',
                        help="Only write batchscript, don't run IGV")
    parser.add_argument("-suffix", dest='suffix', default=None,
                        help="Filename suffix for snapshots")
    parser.add_argument("-nf4", dest='nf4_mode', action='store_true',
                        help="Use 4th BED field as snapshot filename")
    parser.add_argument("-onlysnap", dest='onlysnap', default=False,
                        help="Run existing batchscript file")
    parser.add_argument("-s", "--group-by-strand", dest="group_by_strand",
                        action='store_true', help="Group reads by strand")
    parser.add_argument("-java", dest='java_path',
                        default="/usr/lib/jvm/java-8-openjdk-amd64/bin/java",
                        help="Path to Java 8 executable (default: /usr/lib/jvm/java-8-openjdk-amd64/bin/java)")

    args = parser.parse_args()

    main(
        input_files=args.input_files,
        region_file=args.region_file,
        genome=args.genome,
        image_height=args.image_height,
        outdir=args.outdir,
        igv_jar_bin=args.igv_jar_bin,
        igv_mem=args.igv_mem,
        no_snap=args.no_snap,
        suffix=args.suffix,
        nf4_mode=args.nf4_mode,
        onlysnap=args.onlysnap,
        group_by_strand=args.group_by_strand,
        java_path=args.java_path
    )


if __name__ == "__main__":
    run()
