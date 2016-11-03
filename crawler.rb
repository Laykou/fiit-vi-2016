#!/usr/bin/env ruby

require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'fileutils'
require 'elasticsearch'
require 'optparse'
require 'sanitize'
require 'date'

client = Elasticsearch::Client.new host: '188.167.196.194'

client.cluster.health

BASE_URL = "http://stackoverflow.com"

def url(link)
    BASE_URL + link.to_s
end

ARGV << '-h' if ARGV.empty?

options = {
    tag: 'php',
    page: 1,
    limit: 10
}

OptionParser.new do |opts|
  opts.banner = "Usage: parser.rb [options]"

  opts.on("-t TAG", "--tag=TAG", "Tag to parse") do |value|
    options[:tag] = value
  end

  opts.on("-p PAGE", "--page=PAGE", "Page to start at") do |value|
    options[:page] = value
  end

  opts.on("-l LIMIT", "--limit=LIMIT", "Number of toatal pages to be crawled") do |value|
    options[:limit] = value
  end

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!

current_page = options[:page].to_i

while current_page <= options[:page].to_i + options[:limit].to_i do
    puts "Parsing tag '#{options[:tag]}', page #{current_page} out of #{options[:page].to_i + options[:limit].to_i}"
    base_url = url "/questions/tagged/#{options[:tag]}?page=#{current_page}&sort=votes"

    begin
        index_page = Nokogiri::HTML(open(base_url))
    rescue OpenURI::HTTPError
        puts "OPEN URI ERROR, sleeping..."
        sleep(600)

        index_page = Nokogiri::HTML(open(base_url))
    end

    index_page.css('#questions .question-hyperlink').each do |question|
        data = {}
        data[:link] = question.attribute('href').content
        data[:url] =  url data[:link]

        begin
            question_page = Nokogiri::HTML(open(data[:url]))
        rescue OpenURI::HTTPError
            puts "OPEN URI ERROR, sleeping..."
            sleep(600)

            question_page = Nokogiri::HTML(open(data[:url]))
        end

        data[:title] = question_page.css('#question-header').text.strip

        puts "\tParsing question '#{data[:title]}'"

        data[:id] = question_page.css('#question').attribute('data-questionid').text.to_i
        data[:votes] = question_page.css('#question [itemprop=upvoteCount]').text.to_i
        data[:favorites] = question_page.css('#question .favoritecount').text.to_i
        data[:question] = question_page.css('#question .postcell .post-text').text.strip
        data[:tags] = question_page.css('#question .post-taglist a').map { |x| x.text.strip }
        data[:created] = Date.parse question_page.css('#question .user-action-time .relativetime').attribute('title')

        owner = question_page.css('#question .post-signature.owner .user-details')
        data[:owner] = {
            username: owner.css('a').text.strip,
            reputation: owner.css('.reputation-score').text.to_i,
            gold: owner.css('.gold .badgecount').text.to_i,
            silver: owner.css('.silver .badgecount').text.to_i,
            bronze: owner.css('.bronze .badgecount').text.to_i
        }

        data[:comments] = question_page.css('#question .comments .comment').map do |comment|
            cmnt = {}

            cmnt[:score] = comment.css('.comment-score').text.strip.to_i
            cmnt[:comment] = comment.css('.comment-copy').text.strip
            cmnt[:owner] = comment.css('.comment-user').text.strip
            cmnt[:created] = Date.parse  comment.css('.comment-date .relativetime-clean').attribute('title')

            cmnt
        end

        data[:answers] = question_page.css('#answers .answer').map do |answer|
            answr = {}

            answr[:title] = answer.css('#answer-header').text.strip
            answr[:id] = answer.attribute('data-answerid').text
            answr[:votes] = answer.css('[itemprop=upvoteCount]').text.to_i
            answr[:question] = answer.css('.answercell .post-text').text.strip
            answr[:created] = Date.parse answer.css('.user-action-time .relativetime').attribute('title')

            owner = answer.css('.post-signature .user-details')
            answr[:owner] = {
                username: owner.css('a').text.strip,
                reputation: owner.css('.reputation-score').text.to_i,
                gold: owner.css('.gold .badgecount').text.to_i,
                silver: owner.css('.silver .badgecount').text.to_i,
                bronze: owner.css('.bronze .badgecount').text.to_i
            }

            answr[:comments] = answer.css('.comments .comment').map do |comment|
                cmnt = {}

                cmnt[:score] = comment.css('.comment-score').text.strip.to_i
                cmnt[:comment] = comment.css('.comment-copy').text.strip
                cmnt[:owner] = comment.css('.comment-user').text.strip
                cmnt[:created] = Date.parse  comment.css('.comment-date .relativetime-clean').attribute('title')

                cmnt
            end

            answr
        end

        client.index index: 'questions', type: 'question', id: data[:id], body: data

        sleep(0.7)
        # puts data.inspect
    end

    sleep(5)

    current_page += 1
end
