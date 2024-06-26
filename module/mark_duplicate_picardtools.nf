
// mark duplicates with picard
process run_MarkDuplicate_Picard {
   container params.docker_image_picardtools
   containerOptions "--volume ${params.work_dir}:/temp_dir"

   publishDir path: "${bam_output_dir}",
      pattern: "*.{bam,bai}",
      mode: 'copy',
      saveAs: { filename -> (file(filename).getExtension() == "bai") ? "${file(filename).baseName}.bam.bai" : "${filename}" }

   publishDir path: "${qc_output_dir}/${task.process.split(':')[1].replace('_', '-')}",
      pattern: "*.metrics",
      enabled: params.save_intermediate_files,
      mode: 'copy'

   publishDir path: "${log_output_dir}/${task.process.split(':')[-1].replace('_', '-')}",
      pattern: ".command.*",
      mode: "copy",
      saveAs: { "log${file(it).getName()}" }

   input:
      path(input_bams)
      val(bam_output_dir)
      val(intermediate_output_dir)
      val(log_output_dir)
      val(qc_output_dir)

   // after marking duplicates, bams will be merged by library so the library name is not needed
   // just the sample name (global variable), do not pass it as a val
   output:
      path bam_output_filename, emit: bam
      path "*.bai", emit: bam_index
      path "${bam_output_filename.substring(0, bam_output_filename.length()-4)}.mark_dup.metrics"
      path(".command.*")

   script:
   bam_output_filename = "${params.bam_output_filename}"
   
   """ 
   set -euo pipefail

   # add picard option prefix, '--INPUT' to each input bam
   declare -r INPUT=\$(echo '${input_bams}' | sed -e 's/ / --INPUT /g' | sed '1s/^/--INPUT /')

   java -Xmx${(task.memory - params.gatk_command_mem_diff).getMega()}m -Djava.io.tmpdir=/temp_dir \
      -jar /usr/local/share/picard-slim-3.1.1-0/picard.jar \
      MarkDuplicates \
      --VALIDATION_STRINGENCY LENIENT \
      \$INPUT \
      --OUTPUT ${bam_output_filename} \
      --METRICS_FILE ${bam_output_filename.substring(0, bam_output_filename.length()-4)}.mark_dup.metrics \
      --ASSUME_SORT_ORDER coordinate \
      --PROGRAM_RECORD_ID MarkDuplicates \
      --CREATE_INDEX true
   """
   }
