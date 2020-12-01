# Call DNA Align Nextflow Pipeline for BWA Alignment of Paired-End Reads

1. [Overview](#Overview)
2. [How To Run](#How-To-Run)
3. [Flow Diagram](#Flow-Diagram)
4. [Pipeline Steps](#Pipeline-Steps)
5. [Inputs](#Inputs)
5. [Outputs](#Outputs)
6. [Testing and Validation](#Testing-and-Validation)
7. [References](#References)

## Overview

The align-DNA nextflow pipeline, aligns paired-end data utilizing [BWA-MEM2](https://github.com/bwa-mem2/bwa-mem2), [Picard](https://github.com/broadinstitute/picard) Tools and [Samtools](https://github.com/samtools/samtools). The pipeline has been engineered to run in a 4 layer stack in a cloud-based scalable environment of CycleCloud, Slurm, Nextflow and Docker. Additionally, it has been validated with the SMC-HET dataset and reference GRCh38, where paired-end fastq’s were created with BAM Surgeon.

The pipeline should be run **WITH A SINGLE SAMPLE AT A TIME**. Otherwise resource allocation and Nextflow errors could cause the pipeline to fail.

<b><i>Developer's Notes:</i></b>

> For some reads with low mapping qualities, BWA-MEM2 assigns them to different genomic positions when using different CPU-numbers. If you want to 100% reproduce a run, the same CPU-number (`bwa_mem_number_of_cpus`) needs to be set.

> BWA-MEM2 now only supports five CPU instruction set, AVX, AVX2, AVX512, SSE4.1 and SSE4.2. However we only tested the pipeline on AVX2 and AVX512 CPUs.

> We performed a benchmarking on our SLURM cluster. Using 56 CPUs for alignment (`bwa_mem_number_of_cpus`) gives it the best performance. See [Testing and Validation](#Testing-and-Validation).

---

## How To Run

Pipelines should be run **WITH A SINGLE SAMPLE AT TIME**. Otherwise resource allocation and Nextflow errors could cause the pipeline to fail

1. Make sure the pipeline is already downloaded to yoru machine. You can either download the stable release or the dev version by cloning the repo.  

2. Create a config file for input, output, and parameters. An example can be found [here](pipeline/config/align-DNA.config). See [Inputs](#Inputs) for description of each variables in the config file.

3. Update the input csv. See [Inputs](#Inputs) for the columns needed. All columns must exist in order to run the pipeline. An example can be found [here](pipeline/inputs/align-DNA.inputs.csv). The example csv is a single-lane sample, however this pipeline can take multi-lane sample as well, with each record in the csv file representing a lane (a paire of fastq). All records must have the same value in the **sample** column.

4. See the submission script, [here](https://github.com/uclahs-cds/tool-submit-nf), to submit your pipeline

---

## Flow Diagram

A directed acyclic graph of your pipeline.

![align-DNA flow diagram](flowchart-diagram.drawio.svg?raw=true)

---

## Pipeline Steps

### 1A. Alignment

The first step of the pipeline utilizes [BWA-MEM2](https://github.com/bwa-mem2/bwa-mem2) to align paired reads, (see Tools and Infrastructure Section for details). BWA-MEM2 is the successor for the well-known aligner BWA. The bwa-mem2 mem command utilizes the -M option for marking shorter splitsas secondary. This allows for compatibility with Picard Tools in downstream process and in particular prevents the underlying library of Picard Tools from recognizing these splits as duplicate reads (read names). Additionally, the -t option is utilized toincrease the number of threads used for alignment. The number of threads used in this step is by default to allow at least 2.5Gb memory per CPU, because of the large memory usage by BWA-MEM2. This can be overwritten by setting the bwa_mem_number_of_cpus parameter from the config file. For more details regarding the specific command that was run please refer to the Source Code section.

### 1B. Convert Align SAM File to BAM Format

In the sampe step of the pipeline utilizes Samtool’sview command to convert the aligned SAM files into the compressed BAM format, (see Tools and Infrastructure Section for details). The Samtools view command utilizes the -s option for increasing the speed by removing duplicates and outputs the reads as they are ordered in the file.  Additionally, the -b option ensures the output is in BAM format and the -@ option is utilized to increase the number of threads. For more details regarding the specific command that was run please refer to the Source Code section.

### 2. Sort BAM Files in Coordinate Order

The next step of the pipeline utilizes Picard Tool’s SortSam command to sort the aligned BAM files in coordinate order that is needed for downstream tools, (see Tools and Infrastructure Section for details). The SortSam command utilizes the VALIDATION_STRINGENCY=LENIENT option to indicate how errors should be handled and keep the process running if possible. Additionally, the SORT_ORDER option is utilized to ensure the file is sorted in coordinate order, opposed to being sorted by read group name. For more details regarding the specific command that was run please refer to the Source Code section.

## 3. Mark Duplicates in BAM Files

The next step of the pipeline utilizes Picard Tool’s MarkDuplicates command to mark duplicates in the BAM files, (see Tools and Infrastructure Section for details). The MarkDuplicates command utilizes the VALIDATION_STRINGENCY=LENIENT option to indicate how errors should be handled and keep the process running if possible. Additionally, the Program_Record_Id is set to “MarkDuplicates”. For more details regarding the specific command that was run please refer to the Source Code section

## 4. Index BAM Files

After marking dup BAM files, the BAM files are then indexed by utilizing Picard Tool’sBuildBamIndex command, (see Tools and Infrastructure Section for details). This utilizes the `VALIDATION_STRINGENCY=LENIENT` option to indicate how errors should be handled and keep the process running if possible. For more details regarding the specific command that was run please refer to the Source Code section.

---

## Inputs

### Input CSV Fields

>The input csv must have all columns below and in the same order. An example of an input csv can be found [here](pipeline/inputs/align-DNA.inputs.csv)

| Field | Type | Description |
|:------|:-----|:------------|
| index | integer | The index of input fastq pairs, starting from 1. |
| read_group_identifier | string | The read group each read blongs to. This is concatenated with the `lane` column (see below) and then passed to the `ID` field of the final BAM. No white space is allowed. For more detail see [here](https://gatk.broadinstitute.org/hc/en-us/articles/360035890671-Read-groups). |
| sequencing_center | string | The sequencing center where the data were produced. This is passed to the `CN` field of the final BAM. No white space is allowed. For more detail see [here](https://gatk.broadinstitute.org/hc/en-us/articles/360035890671-Read-groups) |
| library_identifier | string | The library identifier to be passed to the `LB` field of the final BAM. No white space is allowed. For more detail see [here](https://gatk.broadinstitute.org/hc/en-us/articles/360035890671-Read-groups) |
| platform_technology | string | The platform or technology used to produce the reads. This is passed to the `PL` field of the final BAM. No white space is allowed. For more detail see [here](https://gatk.broadinstitute.org/hc/en-us/articles/360035890671-Read-groups) |
| platform_unit | string | The platform unit to be passed to the `PU` field of the final BAM. No white space is allowed. For more detail see [here](https://gatk.broadinstitute.org/hc/en-us/articles/360035890671-Read-groups) |
| sample | string | The sample name to be passed to the `SM` field of the final BAM. No white space is allowed. For more detail see [here](https://gatk.broadinstitute.org/hc/en-us/articles/360035890671-Read-groups) |
| lane | string | The lane name or index. This is concatenated with the `read_group_identifier` column (see above) and then passed to the `ID` field of the final BAM. No white space is allowed. For more detail see [here](https://gatk.broadinstitute.org/hc/en-us/articles/360035890671-Read-groups) |
| read1_fastq | path | Absolute path to the R1 fastq file. |
| read2_fastq | path | Absolute path to the R2 fastq file. |

### Config File Parameters

| Input Parameter | Required | Type | Description |
|:----------------|:---------|:-----|:------------|
| `sample_name` | yes | string | The sample name. This is ignored if the output files are directly saved to the Boutros Lab data storage registry, by setting `blcds_registered_dataset_output = true` |
| `input_csv` | yes | path | Absolute path to the input csv. See [here](pipeline/inputs/align-DNA.inputs.csv) for example and above for the detail of required fields. |
| `reference_fasta` | yes | path | Absolute path to the reference genome `fasta` file. The reference genome is used by BWA-MEM2 for alignment. |
| `reference_fasta_index_files` | yes | path | Absolute path to the genome index with a pattern matching. The index must be generated by the `bwa-mem2 index` command using the correct version of BWA-MEM2. |
| `reference_genome_version` | no | string | The genome build version. This is only used when the output files are directly saved to the Boutros Lab data storage registry, by setting `blcds_registered_dataset_output = true`. |
| `output_dir` | yes | path | Absolute path to the directory where the output files to be saved. This is ignored if the output files are directly saved to the Boutros Lab data storage registry, by setting `blcds_registered_dataset_output = true` |
| `temp_dir` | yes | path | Absolute path to the directory where the nextflow's intermediate files are saved. |
| `save_intermediate_files` | yes | boolean | Save intermediate files. If yes, not only the final BAM, but also the unmerged, unsorted, and duplicates unmarked BAM files will also be saved. |
| `cache_intermediate_pipeline_steps` | yes | boolean | Enable cahcing to resume pipeline and the end of the last successful process completion when a pipeline fails (if true the default submission script must be modified). |
| `max_number_of_parallel_jobs` | yes | int | The maximum number of jobs or steps of the pipeline that can be ran in parallel. |
| `bwa_mem_number_of_cpus` | no | int | Number of cores to use for BWA-MEM2. If not set, this will be calculated to ensure at least 2.5Gb memory per core. |
| `blcds_registered_dataset_input` | yes | boolean | Input FASTQs are from the Boutros Lab data registry. |
| `blcds_registered_dataset_output` | yes | boolean | Enable saving final files including BAM and BAM index, and logging files directory to the Boutros Lab Data registry. |
| `blcds_cluster_slurm` | no | boolean | Pipeline is to run on the Slurm cluster. Set to `false` if it is to run on the SGE cluster. This is used only when `blcds_registered_dataset_output = true` and `blcds_registered_dataset_input = false`. It is also ignored if `blcds_mount_dir` is set. |
| `blcds_disease_id` | no | string | The registered disease ID of this dataset from the Boutros Lab data registry. Ignored if `blcds_registered_data_input = true` or `blcds_registered_output = false` |
| `blcds_dataset_id` | no | string | The registered dataset ID of this dataset from the Boutros Lab data registry. Ignored if `blcds_registered_data_input = true` or `blcds_registered_output = false` |
| `blcds_patient_id` | no | string | The registered patient ID of this sample from the Boutros Lab data registry. Ignored if `blcds_registered_data_input = true` or `blcds_registered_output = false` |
| `blcds_sample_id` | no | string | The registered sample ID from the Boutros Lab data registry. Ignored if `blcds_registered_data_input = true` or `blcds_registered_output = false` |
| `blcds_mount_dir` | no | string | The directoyr that the storage is mounted to (e.g., /hot, /data). |

---

## Outputs

| Output | Description |
|:-------|:------------|
| `.bam` | Aligned, sorted, filtered and if needed, merged, BAM file(s) |
| `.bam.bai` | Index file for each BAM file |
| `.bam` files and metrics files | Intermediate outputs for each scientific tool (OPTIONAL) |
| `report.html`, `timeline.html` and `trace.txt` | A Nextflowreport, timeline and trace files |
| `log.command.*` | Process specific logging files created by nextflow. |

---

## Testing and Validation

### Test Data Set

This pipeline was tested using the synthesized SMC-HET dataset as well as a multi-lane real sample CPCG0196-B1, using reference genome version GRCh38. Some benchmarking has been done comparing BWA-MEM2 v2.1, v2.0, and the original BWA. BWA-MEM2 is able to reduce approximately half of the runtime comparing to the original BWA, with the output BAM almost identical. See [here](https://uclahs.app.box.com/file/737244561716) for the benchmarking.

### Validation <version number\>

| metric | Result | 
|:-------|:-------|
| raw total sequences | 1.0000000 |
| filtered sequences | NaN |
| sequences | 1.0000000 |
| is sorted | 1.0000000 |
| 1st fragments | 1.0000000 |
| last fragments | 1.0000000 |
| reads mapped | 1.0000000 |
| reads mapped and paired | 1.0000001 |
| reads unmapped | 0.9999950 |
| reads properly paired | 0.9999999 |
| reads paired | 1.0000000 |
| reads duplicated | 0.9999949 |
| reads MQ0 | 1.0000009 |
| reads QC failed | NaN |
| non-primary alignments | 0.9999757 |
| total length | 1.0000000 |
| bases mapped | 1.0000000 |
| bases mapped (cigar) | 1.0000000 |
| bases trimmed | NaN |
| bases duplicated | 0.9999958 |
| mismatches | 0.9999987 |
| error rate | 0.9999987 |
| average length | 1.0000000 |
| maximum length | 1.0000000 |
| average quality | 1.0000000 |
| insert size average | 1.0000000 |
| insert size standard deviation | 1.0000000 |
| inward oriented pairs | 0.9999991 |
| outward oriented pairs | 1.0000477 |
| pairs with other orientation | 0.9999726 |
| pairs on different chromosomes | 1.0000416 |

---

## References
