require_relative '../../lib/responder'

module Ropensci
  class ReviewersDueDateResponder < Responder

    keyname :ropensci_reviewers

    def define_listening
      @event_action = "issue_comment.created"
      @event_regex = /\A@#{@bot_name} (add|remove) (\S+) (as reviewer|to reviewers|from reviewers)\s*\z/i
    end

    def process_message(message)
      add_or_remove = @match_data[1].downcase
      reviewer = @match_data[2]
      to_or_from = @match_data[3].downcase

      if !issue_body_has?("reviewers-list")
        respond("I can't find the reviewers list")
        return
      end

      add_to_or_remove_from = [add_or_remove, to_or_from].join(" ")

      if ["add to reviewers", "add as reviewer"].include?(add_to_or_remove_from)
        add reviewer
      elsif add_to_or_remove_from == "remove from reviewers"
        remove reviewer
      else
        respond("That command is confusing. Did you mean to ADD TO reviewers or to REMOVE FROM reviewers?")
      end
    end

    def add(reviewer)
      if list_of_values.include?(reviewer)
        respond("#{reviewer} is already included in the reviewers list")
      else
        new_list = (list_of_values + [reviewer]).uniq
        update_list("reviewers", new_list.join(", "))
        respond("#{reviewer} added to the reviewers list!")
        add_collaborator(reviewer) if add_as_collaborator?(reviewer)
        add_assignee(reviewer) if add_as_assignee?(reviewer)
        process_labeling if new_list.size == 2
      end
    end

    def remove(reviewer)
      if list_of_values.include?(reviewer)
        new_list = (list_of_values - [reviewer]).uniq
        updated_list = new_list.empty? ? no_reviewer_text : new_list.join(", ")
        update_list("reviewers", updated_list)
        respond("#{reviewer} removed from the reviewers list!")
        remove_assignee(reviewer) if add_as_assignee?(reviewer)
        process_reverse_labeling if new_list.size == 1
      else
        respond("#{reviewer} is not in the reviewers list")
      end
    end

    def list_of_values
      @list_of_values ||= read_value_from_body("reviewers-list").split(",").map(&:strip)-[no_reviewer_text]
    end

    def no_reviewer_text
      params[:no_reviewer_text] || 'TBD'
    end

    def add_as_collaborator?(value)
      username?(value) && params[:add_as_collaborator] == true
    end

    def add_as_assignee?(value)
      username?(value) && params[:add_as_assignee] == true
    end

    def description
      ["Add a user to this issue's reviewers list",
       "Remove a user from the reviewers list"]
    end

    def example_invocation
      ["@#{@bot_name} add #{params[:sample_value] || 'xxxxx'} to reviewers",
       "@#{@bot_name} remove #{params[:sample_value] || 'xxxxx'} from reviewers"]
    end
  end
end
