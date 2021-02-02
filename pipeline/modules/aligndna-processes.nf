include { validate_file } from './validation.nf'

workflow aligndna {
   take:
      ich_samples
      ich_reference_fasta
      ich_reference_index_files
   main:
      align_BWA_mem_convert_SAM_to_BAM_samtools(
         ich_samples,
         ich_reference_fasta,
         ich_reference_index_files.collect()
      )
      PicardTools_SortSam(align_BWA_mem_convert_SAM_to_BAM_samtools.out)
      PicardTools_MarkDuplicates(PicardTools_SortSam.out.collect())
      PicardTools_BuildBamIndex(PicardTools_MarkDuplicates.out)
      generate_sha512sum(PicardTools_BuildBamIndex.out.mix(PicardTools_MarkDuplicates.out))
      validate_file(
         PicardTools_MarkDuplicates.out.mix(
            generate_sha512sum.out,
            PicardTools_BuildBamIndex.out,
            Channel.from(params.temp_dir, params.output_dir)
         )
      )
   //emit:
      // TODO change this
      //align_BWA_mem_convert_SAM_to_BAM_samtools
}

// align with bwa mem and convert with samtools
process align_BWA_mem_convert_SAM_to_BAM_samtools {
   container params.docker_image_bwa_and_samtools
   publishDir path: params.bam_output_dir,
      enabled: params.save_intermediate_files,
      pattern: "*.bam",
      mode: 'copy'

   publishDir path: params.log_output_dir,
      pattern: ".command.*",
      mode: "copy",
      saveAs: { "align_BWA_mem_convert_SAM_to_BAM_samtools/${file(read1_fastq).getSimpleName()}/log${file(it).getName()}" }

   memory params.amount_of_memory
   cpus params.bwa_mem_number_of_cpus

   // use "each" so the the reference files are passed through for each fastq pair alignment 
   input: 
      tuple(val(library), 
         val(lane),
         val(read_group_name), 
         path(read1_fastq),
         path(read2_fastq) 
      )
      each file(ref_fasta)
      file(ich_reference_index_files)

   // output the lane information in the file name to differentiate bewteen aligments of the same
   // sample but different lanes
   output:
      tuple(val(library), 
         val(lane),
         file("${library}-${lane}.aligned.bam")
      )
      //file ".command.*"
      // into och_align_BWA_mem_convert_SAM_to_BAM_samtools

   script:
   """
   set -euo pipefail

   bwa-mem2 \
      mem \
      -t ${task.cpus} \
      -M \
      -R "${read_group_name}" \
      ${ref_fasta} \
      ${read1_fastq} \
      ${read2_fastq} | \
   samtools \
      view \
      -@ ${task.cpus} \
      -S \
      -b > \
      ${library}-${lane}.aligned.bam
   """
}

// sort coordinate order with picard
process PicardTools_SortSam  {
   container params.docker_image_picardtools
   containerOptions "--volume ${params.temp_dir}:/temp_dir"
   
   publishDir path: params.output_dir,
      enabled: params.save_intermediate_files,
      pattern: "*.sorted.bam",
      mode: 'copy'

   publishDir path: params.log_output_dir,
      pattern: ".command.*",
      mode: "copy",
      saveAs: { "PicardTools_SortSam/log${file(it).getName()}" }

   memory params.amount_of_memory
   cpus params.number_of_cpus

   input:
      tuple(val(library), 
         val(lane),
         file(input_bam)
      )// from och_align_BWA_mem_convert_SAM_to_BAM_samtools
   
   // the first value of the tuple will be used as a key to group aligned and filtered bams
   // from the same sample and library but different lane together

   // the next steps of the pipeline are merging so using a lane to differentiate between files is no londer needed
   // (files of same lane are merged together) so the lane information is dropped
   output:
      file("${library}-${lane}.sorted.bam")// into och_PicardTools_SortSam
      //file ".command.*"

   script:
   """
   set -euo pipefail

   java -Xmx${params.mem_command_sort_sam} -Djava.io.tmpdir=/temp_dir \
      -jar /picard-tools/picard.jar \
      SortSam \
      --VALIDATION_STRINGENCY LENIENT \
      --INPUT ${input_bam} \
      --OUTPUT ${library}-${lane}.sorted.bam \
      --SORT_ORDER coordinate
   """
}

// mark duplicates with picard
process PicardTools_MarkDuplicates  {
   container params.docker_image_picardtools
   containerOptions "--volume ${params.temp_dir}:/temp_dir"

   publishDir path: params.bam_output_dir,
      pattern: "*.bam",
      mode: 'copy'

   publishDir path: params.log_output_dir,
      pattern: ".command.*",
      mode: "copy",
      saveAs: { "PicardTools_MarkDuplicates/log${file(it).getName()}" }

   memory params.amount_of_memory
   cpus params.number_of_cpus

   input:
      file(input_bams)

   // after marking duplicates, bams will be merged by library so the library name is not needed
   // just the sample name (global variable), do not pass it as a val
   output:
      file(bam_output_filename)

   shell:
   bam_output_filename = params.bam_output_filename
   ''' 
   set -euo pipefail

   # add picard option prefix, '--INPUT' to each input bam
   declare -r INPUT=$(echo '!{input_bams}' | sed -e 's/ / --INPUT /g' | sed '1s/^/--INPUT /')

   java -Xmx!{params.mem_command_mark_duplicates} -Djava.io.tmpdir=/temp_dir \
      -jar /picard-tools/picard.jar \
      MarkDuplicates \
      --VALIDATION_STRINGENCY LENIENT \
      $INPUT \
      --OUTPUT !{bam_output_filename} \
      --METRICS_FILE !{params.sample_name}.mark_dup.metrics \
      --ASSUME_SORT_ORDER coordinate \
      --PROGRAM_RECORD_ID MarkDuplicates
   '''
}

// index bams with picard
process PicardTools_BuildBamIndex  {
   container params.docker_image_picardtools
   containerOptions "--volume ${params.temp_dir}:/temp_dir"

   publishDir path: params.bam_output_dir,
      pattern: "*.bam.bai",
      mode: 'copy'

   publishDir path: params.log_output_dir,
      pattern: ".command.*",
      mode: "copy",
      saveAs: { "PicardTools_BuildBamIndex/log${file(it).getName()}" }

   memory params.amount_of_memory
   cpus params.number_of_cpus
   
   input:
      file(input_bam)

   // no need for an output channel becuase this is the final stepp
   output:
      file("${input_bam.getName()}.bai")

   script:
   """
   set -euo pipefail

   java -Xmx${params.mem_command_build_bam_index} -Djava.io.tmpdir=/temp_dir \
      -jar /picard-tools/picard.jar \
      BuildBamIndex \
      --VALIDATION_STRINGENCY LENIENT \
      --INPUT ${input_bam} \
      --OUTPUT ${input_bam.getName()}.bai
   """
}

// produce checksum for the bam and bam index
process generate_sha512sum {    
   container params.docker_image_sha512sum

   publishDir path: params.bam_output_dir, mode: 'copy'
   
   memory params.amount_of_memory
   cpus params.number_of_cpus

   input:
      file(input_file)

   output:
      file("${input_file.getName()}.sha512")

   script:
   """
   set -euo pipefail

   sha512sum ${input_file} > ${input_file.getName()}.sha512
   """
}