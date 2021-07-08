require 'airrecord'

module Ropensci
  class AirtableWorker < BuffyWorker

    attr_accessor :params, :airtable_config

    def perform(action, config, locals, params)
      load_context_and_env(locals)
      @params = OpenStruct.new(params)
      @airtable_config = { api_key: buffy_settings['env']['airtable_api_key'],
                           base_id: buffy_settings['env']['airtable_base_id'] }
      case action.to_sym
      when :assign_reviewer
        assign_reviewer
      when :remove_reviewer
        remove_reviewer
      when :slack_invites
        slack_invites
      end
    end

    def assign_reviewer
      reviewer = user_login(params.reviewer.to_s)
      begin
        gh_user = Octokit.user(reviewer)
      rescue Octokit::NotFound
        respond("I could not find user @#{reviewer}") and return
      end

      if gh_user
        # Check if reviewer present in Airtable reviewers-prod or create it
        reviewer_entry = airtable_revs.all(filter: "{github} = '#{gh_user.login}'").first ||
                            airtable_revs.create(github: gh_user.login, name: gh_user.name, email: gh_user.email)

        # Add current_assignment to reviewers
        reviewer_entry["current_assignment"] = "https://github.com/#{context.repo}/#{context.issue_id}"
        reviewer_entry.save

        # Add entry in the **reviews** airtable
        airtable_reviews.create(id_no: "#{context.issue_id}",
                       github: [reviewer_entry.id],
                       onboarding_url: reviewer_entry["current_assignment"],
                       package: params.package_name)

        # Respond to GH with:
        respond("@#{gh_user.login}: If you haven't done so, please fill [this form](https://airtable.com/shrnfDI2S9uuyxtDw) for us to update our reviewers records.")
      end
    end

    def remove_reviewer
      reviewer = user_login(params.reviewer.to_s)

      # Delete current assignment
      reviewer_entry = airtable_revs.all(filter: "{github} = '#{reviewer}'").first
      if reviewer_entry
        reviewer_entry["current_assignment"] = ""
        reviewer_entry.save
      end

      # Delete review entry
      review_entry = airtable_reviews.all(filter: "AND({github} = '#{reviewer}', {id_no} = '#{context.issue_id}')").first
      if review_entry
        review_entry.destroy
      end
    end

    def slack_invites
      author = begin
        Octokit.user(params.author)
      rescue Octokit::NotFound
        nil
      end

      reviewers = []
      params.reviewers.each do |reviewer|
        reviewers << begin
          Octokit.user(reviewer)
        rescue Octokit::NotFound
          nil
        end
      end

      author_others = []
      params.author_others.each do |other|
        author_others << begin
          Octokit.user(other)
        rescue Octokit::NotFound
          nil
        end
      end

      if author
        airtable_slack_invites.create(package: params.package_name,
                                      name: name_or_github_login(author),
                                      email: author.email,
                                      github: "https://github.com/#{author.login}",
                                      date: Time.now.strftime("%m/%d/%Y"),
                                      role: "author1")
      end

      reviewers.uniq.compact.each do |reviewer|
        airtable_slack_invites.create(package: params.package_name,
                                      name: name_or_github_login(reviewer),
                                      email: reviewer.email,
                                      github: "https://github.com/#{reviewer.login}",
                                      date: Time.now.strftime("%m/%d/%Y"),
                                      role: "reviewer")
      end

      author_others.uniq.compact.each do |other|
        airtable_slack_invites.create(package: params.package_name,
                                      name: name_or_github_login(other),
                                      email: other.email,
                                      github: "https://github.com/#{other.login}",
                                      date: Time.now.strftime("%m/%d/%Y"),
                                      role: "author-others")
      end
    end

    private

    def airtable_revs
      @airtable_reviewers_table ||= Airrecord.table(airtable_config[:api_key], airtable_config[:base_id], "reviewers-prod")
    end

    def airtable_reviews
      @airtable_reviews_table ||= Airrecord.table(airtable_config[:api_key], airtable_config[:base_id], "reviews")
    end

    def airtable_slack_invites
      @airtable_slack_invites_table ||= Airrecord.table(airtable_config[:api_key], airtable_config[:base_id], "slack-invites")
    end

    def name_or_github_login(gh_user)
      if gh_user.name.nil? || gh_user.name.empty?
        return "#{gh_user.login} (GitHub username)"
      else
        return gh_user.name
      end
    end
  end
end
