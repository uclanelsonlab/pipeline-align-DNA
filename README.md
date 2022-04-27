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

The align-DNA nextflow pipeline, aligns paired-end data utilizing [BWA-MEM2](https://github.com/bwa-mem2/bwa-mem2) and/or [HISAT2](http://daehwankimlab.github.io/hisat2/main), [Picard](https://github.com/broadinstitute/picard) Tools and [Samtools](https://github.com/samtools/samtools). The pipeline has been engineered to run in a 4 layer stack in a cloud-based scalable environment of CycleCloud, Slurm, Nextflow and Docker. Additionally, it has been validated with the SMC-HET dataset and reference GRCh38, where paired-end fastq’s were created with BAM Surgeon.

The pipeline should be run **WITH A SINGLE SAMPLE AT A TIME**. Otherwise resource allocation and Nextflow errors could cause the pipeline to fail.

<b><i>Developer's Notes:</i></b>

> For some reads with low mapping qualities, BWA-MEM2 assigns them to different genomic positions when using different CPU-numbers. If you want to 100% reproduce a run, the same CPU-number (`bwa_mem_number_of_cpus`) needs to be set.

> BWA-MEM2 now only supports five CPU instruction set, AVX, AVX2, AVX512, SSE4.1 and SSE4.2. However we only tested the pipeline on AVX2 and AVX512 CPUs.

> We performed a benchmarking on our SLURM cluster. Using 56 CPUs for alignment (`bwa_mem_number_of_cpus`) gives it the best performance. See [Testing and Validation](#Testing-and-Validation).

---

## How To Run

Pipelines should be run **WITH A SINGLE SAMPLE AT TIME**. Otherwise resource allocation and Nextflow errors could cause the pipeline to fail.

1. Make sure the pipeline is already downloaded to your machine. You can either download the stable release or the dev version by cloning the repo.

2. Create a config file for input, output, and parameters. An example for a config file can be found [here](pipeline/nextflow.example.config). See [Inputs](#Inputs) for the detailed description of each variable in the config file. The config file can be generated using a python script (see below).

3. Create the input csv using the [template](pipeline/inputs/align-DNA.inputs.csv). The example csv is a single-lane sample, however this pipeline can take multi-lane sample as well, with each record in the csv file representing a lane (a paire of fastq). All records must have the same value in the **sample** column. See [Inputs](#Inputs) for detailed description of each column. All columns must exist in order to run the pipeline successfully.

4. The pipeline can be executed locally using the command below:

```bash
nextflow run path/to/align-DNA.nf -config path/to/sample-specific.config
```

To submit to UCLAHS-CDS's Azure cloud, use the submission script [here](https://github.com/uclahs-cds/tool-submit-nf) with the command below:

```bash
python path/to/submit_nextflow_pipeline.py \
    --nextflow_script path/to/pipeline-align-DNA.nf \
    --nextflow_config path/to/sample-specific.config \
    --pipeline_run_name <sample_name> \
    --partition_type F72 \
    --email jdoe@ucla.edu
```

<b><i> BWA-MEM2 Genome Index </i></b>
The reference genome index must be generated by BWA-MEM2 with the correct version. Genome index generated by old BWA-MEM2 versions or the original BWA is not accepted. The reference genome index can be generated using the [`generate-genme-index.nf`](pipeline/generate-genome-index.nf) nextflow pipeline. To run this pipeline, you need to create a config file using this [template](pipeline/config/index.config) to specify the path of `reference_fasta` and the `temp_dir`. The `temp_dir` is used to store intermediate files of nextflow. The genome index files are saved to the same directory of the input reference FASTA by the pipeline. Use the command below to run this generate genome index pipeline:

```bash
nextflow run path/to/generate-genome-index.nf -config path/to/genome-specific.config
```

This can also be submitted using the [submission script](https://github.com/uclahs-cds/tool-submit-nf) to the UCLAHS-CDS's Azure cloud as mentioned above.

> The BWA-MEM2 expects the reference genome index to be at the same directory as the reference genome FASTA, so it's important to keep them together.

<b><i> HISAT2 Genome Index </i></b>
The reference genome index must be generated from HISAT2 using [hisat2-build](http://daehwankimlab.github.io/hisat2/howto/). When passing the hisat2 index to the config, only the path up to the prefix(basename) must be specified:

> The basename is the name of any of the index files up to but not including the final .1.ht2 / etc. hisat2 looks for the specified index first in the current directory, then in the directory specified in the HISAT2_INDEXES environment variable.

<b><i> Generating the config file using a script </i></b>

To learn how to run the script, use one of the following commands:
```bash
python path/to/pipeline-align-DNA/script/write_dna_align_config_file.py -h
python path/to/pipeline-align-DNA/script/write_dna_align_config_file.py param
python path/to/pipeline-align-DNA/script/write_dna_align_config_file.py example

```

See the following command for example:
```bash
python path/to/pipeline-align-DNA/script/write_dna_align_config_file.py \
	/my/path/to/sample_name.csv \
	bwa-mem2 \
	/hot/ref/hg38/bwa-mem2/v2.1/genome.fa \
	/my/path/to/output_directory \
	/my/path/to/temp_directory \
	--save_intermediate_files \
	--cache_intermediate_pipeline_steps
```
---

## Flow Diagram

A directed acyclic graph of your pipeline.

>Following alignment, processes are run separately for each aligner used.

![align-DNA flow diagram](flowchart-diagram.drawio.svg?raw=true)

---

## Pipeline Steps

### 1A. Alignment

The first step of the pipeline utilizes [BWA-MEM2](https://github.com/bwa-mem2/bwa-mem2) or [HISAT2](http://daehwankimlab.github.io/hisat2/main) to align paired reads, (see Tools and Infrastructure Section for details). BWA-MEM2 is the successor for the well-known aligner BWA. The bwa-mem2 mem command utilizes the -M option for marking shorter splits as secondary. This allows for compatibility with Picard Tools in downstream process and in particular prevents the underlying library of Picard Tools from recognizing these splits as duplicate reads (read names). Additionally, the -t option is utilized toincrease the number of threads used for alignment. The number of threads used in this step is by default to allow at least 2.5Gb memory per CPU, because of the large memory usage by BWA-MEM2. This can be overwritten by setting the bwa_mem_number_of_cpus parameter from the config file. For more details regarding the specific command that was run please refer to the Source Code section.

### 1B. Convert Align SAM File to BAM Format

In the sampe step of the pipeline utilizes Samtool’sview command to convert the aligned SAM files into the compressed BAM format, (see Tools and Infrastructure Section for details). The Samtools view command utilizes the -s option for increasing the speed by removing duplicates and outputs the reads as they are ordered in the file.  Additionally, the -b option ensures the output is in BAM format and the -@ option is utilized to increase the number of threads. For more details regarding the specific command that was run please refer to the Source Code section.

### 2. Sort BAM Files in Coordinate or Queryname Order

The next step of the pipeline utilizes Picard Tool’s `SortSam` command to sort the aligned BAM files in coordinate order or queryname order that is needed for downstream tools, (see Tools and Infrastructure Section for details). The `SortSam` command utilizes the `VALIDATION_STRINGENCY=LENIENT` option to indicate how errors should be handled and keep the process running if possible. Additionally, the `SORT_ORDER` option is utilized to ensure the file is sorted in coordinate order or queryname order depending on the downstream Mark Duplicates tool, since Picard and Spark have different sort-order requirements. For more details regarding the specific command that was run please refer to the Source Code section.

For certain use-cases the pipeline may be configured to stop after this step using the mark_duplicates parameter in the config file. In this case the file is sorted in coordinate order and the `SortSam` command utilizes the `CREATE_INDEX` option to index the sorted BAM file. This option is intended for datasets generated with targeted sequencing panels (like our custom Proseq-G Prostate panel). High coverage target enrichment sequencing (like Illumina's [protocol](https://www.illumina.com/techniques/sequencing/dna-sequencing/targeted-resequencing/target-enrichment.html)) results in a large amount of read duplication that is not an artifact of PCR amplification. Marking these reads as duplicates will severely reduce coverage, and it is recommended that the pipeline be configured to not mark duplicates in this case.

## 3. Mark Duplicates in BAM Files

The next step of the pipeline utilizes Picard Tool’s `MarkDuplicates` command to mark duplicates in the BAM files, (see Tools and Infrastructure Section for details). The `MarkDuplicates` command utilizes the `VALIDATION_STRINGENCY=LENIENT` option to indicate how errors should be handled and keep the process running if possible. Additionally, the Program_Record_Id is set to “MarkDuplicates”. For more details regarding the specific command that was run please refer to the Source Code section.

A faster Spark implementation of MarkDuplicates can also be used (MarkDuplicatesSpark from GATK). The process matches the output of Picard's MarkDuplicates with significant runtime improvements. An important note, however, the Spark version requires more disk space and can fail with large inputs with multiple aligners being specified due to insufficient disk space. In such cases, Picard's MarkDuplicates should be used instead.

## 4. Index BAM Files

After marking dup BAM files, the BAM files are then indexed by utilizing Picard Tool’s `BuildBamIndex` command, (see Tools and Infrastructure Section for details). This utilizes the `VALIDATION_STRINGENCY=LENIENT` option to indicate how errors should be handled and keep the process running if possible. For more details regarding the specific command that was run please refer to the Source Code section.

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
| `reference_fasta_bwa` | yes for BWA-MEM2 | path | Absolute path to the reference genome `fasta` file. The reference genome is used by BWA-MEM2 for alignment. |
| `reference_fasta_hisat2` | yes for HISAT2 | path | Absolute path to the reference genome `fasta` file. The reference genome is used by HISAT2 for alignment. |
| `hisat2_index_prefix` | yes for HISAT2 | path | Absolute path up to the genome index basename. The index must be generated by the `hisat2-build` command. |
| `aligner` | yes | list | Which aligners to use as strings in list format. Current options: `BWA-MEM2, HISAT2`. |
| `reference_genome_version` | no | string | The genome build version. This is only used when the output files are directly saved to the Boutros Lab data storage registry, by setting `blcds_registered_dataset_output = true`. |
| `output_dir` | yes | path | Absolute path to the directory where the output files to be saved. This is ignored if the output files are directly saved to the Boutros Lab data storage registry, by setting `blcds_registered_dataset_output = true` |
| `save_intermediate_files` | yes | boolean | Save intermediate files. If yes, not only the final BAM, but also the unmerged, unsorted, and duplicates unmarked BAM files will also be saved. |
| `cache_intermediate_pipeline_steps` | yes | boolean | Enable cahcing to resume pipeline and the end of the last successful process completion when a pipeline fails (if true the default submission script must be modified). |
| `mark_duplicates` | no | boolean | Disable processes which mark duplicates. When false, the pipeline stops at the sorting step, outputting a sorted, indexed, unmerged BAM with unmarked duplicates. Recommended for high coverage targeted panel sequencing datasets. Defaults as true to mark duplicates as usual.|
| `enable_spark` | yes | boolean | Enable use of Spark processes. When true, `MarkDuplicatesSpark` will be used. When false, `MarkDuplicates` will be used. Default value is true. |
| `spark_temp_dir` | no | path | Path to temp dir for Spark processes. When included in the sample config file, Spark intermediate files will be saved to this directory. Defaults to `/scratch` and should only be changed for testing/development. Changing this directory to `/hot` or `/tmp` can lead to high server latency and potential disk space limitations, respectively.|
| `spark_metrics` | no | boolean | should Spark generate *.mark_dup.metrics |
| `work_dir` | no | path | Path of working directory for Nextflow. When included in the sample config file, Nextflow intermediate files and logs will be saved to this directory. With ucla_cds, the default is `/scratch` and should only be changed for testing/development. Changing this directory to `/hot` or `/tmp` can lead to high server latency and potential disk space limitations, respectively. |
| `max_number_of_parallel_jobs` | no | int | The maximum number of jobs or steps of the pipeline that can be ran in parallel. Default is 1. Be very cautious setting this to any value larger than 1, as it may cause out-of-memory error. It may be helpful when running on a big memory computing node. |
| `bwa_mem_number_of_cpus` | no | int | Number of cores to use for BWA-MEM2. If not set, this will be calculated to ensure at least 2.5Gb memory per core. |
| `blcds_registered_dataset_input` | yes | boolean | Input FASTQs are from the Boutros Lab data registry. |
| `blcds_registered_dataset_output` | yes | boolean | Enable saving final files including BAM and BAM index, and logging files directory to the Boutros Lab Data registry. |
| `blcds_cluster_slurm` | no | boolean | Pipeline is to run on the Slurm cluster. Set to `false` if it is to run on the SGE cluster. This is used only when `blcds_registered_dataset_output = true` and `blcds_registered_dataset_input = false`. It is also ignored if `blcds_mount_dir` is set. |
| `blcds_disease_id` | no | string | The registered disease ID of this dataset from the Boutros Lab data registry. Ignored if `blcds_registered_data_input = true` or `blcds_registered_output = false` |
| `blcds_dataset_id` | no | string | The registered dataset ID of this dataset from the Boutros Lab data registry. Ignored if `blcds_registered_data_input = true` or `blcds_registered_output = false` |
| `blcds_patient_id` | no | string | The registered patient ID of this sample from the Boutros Lab data registry. Ignored if `blcds_registered_data_input = true` or `blcds_registered_output = false` |
| `blcds_sample_id` | no | string | The registered sample ID from the Boutros Lab data registry. Ignored if `blcds_registered_data_input = true` or `blcds_registered_output = false` |
| `blcds_mount_dir` | no | string | The directoyr that the storage is mounted to (e.g., /hot, /data). |
| `check_node_config` | no | boolean | Whether to check pre-configured node settings used to set CPU and memory constraints. The default behavior, whether `true` or undefined is to check the pre-configured node settings. Set to `false` to skip this check. |

---

## Outputs

>Separate folders for each aligner used are created to store bam files while a base folder is used to store overall Nextflow information.

| Output | Description | Folder |
|:-------|:------------|:-------|
| `.bam` | Aligned, sorted, filtered and if needed, merged, BAM file(s) | align-DNA-*DATE*/*ALIGNER* |
| `.bam.bai` | Index file for each BAM file | align-DNA-*DATE*/*ALIGNER* |
| `.bam` files and metrics files | Intermediate outputs for each scientific tool (OPTIONAL) | align-DNA-*DATE*/*ALIGNER* |
| `report.html`, `timeline.html` and `trace.txt` | A Nextflowreport, timeline and trace files | align-DNA-*DATE*/log |
| `log.command.*` | Process specific logging files created by nextflow. | align-DNA-*DATE* |

---

## Testing and Validation

### Test Data Set

This pipeline was tested using the synthesized SMC-HET dataset as well as a multi-lane real sample CPCG0196-B1, using reference genome version GRCh38. Some benchmarking has been done comparing BWA-MEM2 v2.1, v2.0, and the original BWA. BWA-MEM2 is able to reduce approximately half of the runtime comparing to the original BWA, with the output BAM almost identical. See [here](docs/benchmarking.md) for the benchmarking.

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

Vasimuddin Md, Sanchit Misra, Heng Li, Srinivas Aluru. Efficient Architecture-Aware Acceleration of BWA-MEM for Multicore Systems. IEEE Parallel and Distributed Processing Symposium (IPDPS), 2019.

Daehwan Kim, Ben Langmead, Steven L Salzberg. HISAT: a fast spliced aligner with low memory requirements. Nature Methods, 2015

---

## License

Authors: Benjamin Carlin, Chenghao Zhu (ChenghaoZhu@mednet.ucla.edu), Aaron Holmes (AHolmes@mednet.ucla.edu), Takafumi Yamaguchi (TYamaguchi@mednet.ucla.edu), Aakarsh Anand (AakarshAnand@mednet.ucla.edu), Yash Patel (YashPatel@mednet.ucla.edu)

Align-DNA is licensed under the GNU General Public License version 2. See the file LICENSE for the terms of the GNU GPL license.

Align-DNA aligned paired-end reads using the BWA-MEM2 and/or HISAT2 aligners.

Copyright (C) 2021 University of California Los Angeles ("Boutros Lab") All rights reserved.

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
