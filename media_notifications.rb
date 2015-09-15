require 'aws-sdk'
require 'yaml'

@config = YAML::load_file(File.join(File.dirname(__FILE__), 'config.yml'))
@new_titles = []

MAX_SUBJECT_LENGTH = 100
VIDEO_EXTENSIONS = %w{avi mkv mp4 m4v mov mpg}

@config['watch_directories'].each do |dir|
	seen_path = File.join(dir, '.seen')

	if File.exists?(seen_path)
		seen_files = File.read(seen_path).split("\n")
	else
		seen_files = []
	end

	current_files = Dir[File.join(dir, "**/*.{#{VIDEO_EXTENSIONS.join(',')}}")]
	new_files = current_files - seen_files

	@new_titles += new_files.map do |new_file|
		basename = File.basename(new_file, '.*')
		tv_matches = basename.match /(.*)S(\d\d)E(\d\d)/i # some.kind.of.title.S01E02.whatever.mkv
		if tv_matches
			title = tv_matches[1].gsub('.', ' ').chop.gsub(/\w+/, &:capitalize)
			episode = "#{tv_matches[2].to_i}-#{tv_matches[3].to_i}"
			"#{title} #{episode}"
		else
			basename
		end
	end

	File.open(seen_path, 'w') do |file|
		file.write(current_files.join("\n"))
	end
end

if @new_titles.length == 0
	puts '0 new'
else
	message = "#{@new_titles.length} new: #{@new_titles.join(', ')}"
	if message.length > MAX_SUBJECT_LENGTH
		subject = "#{message[0..(MAX_SUBJECT_LENGTH - 4)]}..."
	else
		subject = message
	end

	puts message

	if !@config['dry_run']
		sns = Aws::SNS::Client.new(
			:region => @config['region'],
			:access_key_id => @config['access_key_id'],
			:secret_access_key => @config['secret_access_key']
		)

		topic = sns.list_topics.topics.select { |t| t.topic_arn.end_with?('media-notifications') }.first

		sns.publish(
			:topic_arn => topic.topic_arn,
			:message => message,
			:subject => subject
		)
	end
end
