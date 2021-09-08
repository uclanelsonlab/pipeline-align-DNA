// The follwing process runs both alignment and SAM conversion in the same process.
// While this is normally considered to go against the best practices for processes,
// here it actually saves cost, time, and memory to directly pipe the output into 
// samtools due to the large size of the uncompressed SAM files.

include { run_validate; run_validate as validate_output_file } from './run_validate.nf'
include { run_SortSam_Picard } from './sort_bam_picardtools.nf'
include { run_MarkDuplicate_Picard } from './mark_duplicate_picardtools.nf'
include { run_BuildBamIndex_Picard } from './index_bam_picardtools.nf'
include { Generate_Sha512sum } from './check_512sum.nf'

process align_DNA_HISAT2 {
   container params.docker_image_hisat2_and_samtools
   publishDir path: "${params.bam_output_dir}/${params.hisat2_version}",
      enabled: params.save_intermediate_files,
      pattern: "*.bam",
      mode: 'copy'

   publishDir path: "${params.log_output_dir}/${task.process.replace(':', '/')}",
      pattern: ".command.*",
      mode: "copy",
      saveAs: { "${file(read1_fastq).getSimpleName()}/${library}-${lane}.log${file(it).getName()}" }

   // use "each" so the the reference files are passed through for each fastq pair alignment 
   input: 
      tuple(val(library),
         val(header), 
         val(lane), 
         path(read1_fastq),
         path(read2_fastq) 
         )
      each path(ref_fasta)
      path(ich_reference_index_files)

   // output the lane information in the file name to differentiate bewteen aligments of the same
   // sample but different lanes
   output:
      tuple val(library), 
         val(lane),
         path("${library}-${lane}.bam"), emit: bam
      path(".command.*")

   script: 
   """
   set -euo pipefail

   hisat2 \
      -p ${task.cpus} \
      --rg-id ${header.read_group_identifier}.Seq${header.lane} \
      --rg LB:${header.library_identifier} \
      --rg PL:${header.platform_technology} \
      --rg PU:${header.platform_unit} \
      --rg SM:${header.sample} \
      --no-spliced-alignment \
      -x ${file(ich_reference_index_files.get(0).baseName).baseName} \
      -1 ${read1_fastq} \
      -2 ${read2_fastq} | \
   samtools \
      view \
      -@ ${task.cpus} \
      -S \
      -b > \
      ${library}-${lane}.bam
   """
   }

workflow align_DNA_HISAT2_workflow {
   aligner_output_dir = "${params.bam_output_dir}/${params.hisat2_version}"
   take:
      ich_samples
      ich_samples_validate
      ich_reference_fasta
      ich_reference_index_files
   main:
      run_validate(ich_samples_validate.mix(
         ich_reference_fasta,
         ich_reference_index_files
         ))
      align_DNA_HISAT2(
         ich_samples,
         ich_reference_fasta,
         ich_reference_index_files.collect()
         )
      run_SortSam_Picard(align_DNA_HISAT2.out.bam, aligner_output_dir)
      run_MarkDuplicate_Picard(run_SortSam_Picard.out.bam.collect(), aligner_output_dir)
      run_BuildBamIndex_Picard(run_MarkDuplicate_Picard.out.bam, aligner_output_dir)
      Generate_Sha512sum(run_BuildBamIndex_Picard.out.bai.mix(run_MarkDuplicate_Picard.out.bam), aligner_output_dir)
      validate_output_file(
         run_MarkDuplicate_Picard.out.bam.mix(
            run_BuildBamIndex_Picard.out.bai,
            Channel.from(params.temp_dir, params.output_dir)
            )
         )
   }
