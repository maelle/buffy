require_relative "../../spec_helper.rb"

describe Ropensci::ReviewersDueDateResponder do

  subject do
    described_class
  end

  before do
    settings = { env: {bot_github_user: "ropensci-review-bot"} }
    params = { airtable_token: "1234567890", no_reviewer_text: "TBD" }
    @responder = subject.new(settings, params)
  end

  describe "listening" do
    it "should listen to new comments" do
      expect(@responder.event_action).to eq("issue_comment.created")
    end

    it "should define regex" do
      expect(@responder.event_regex).to match("@ropensci-review-bot add @maelle to reviewers")
      expect(@responder.event_regex).to match("@ropensci-review-bot add @maelle as reviewer")
      expect(@responder.event_regex).to match("@ropensci-review-bot remove @maelle from reviewers  \r\n")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot add to reviewers")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot add as reviewers")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot remove   from reviewers")
    end
  end

  describe "#process_message" do
    before do
      disable_github_calls_for(@responder)
      @responder.context = OpenStruct.new(issue_id: 32,
                                          issue_author: "opener",
                                          repo: "openjournals/testing",
                                          sender: "xuanxu")
    end

    describe "adding user as reviewer" do
      before do
        @msg = "@ropensci-review-bot add @xuanxu to reviewers"
        @responder.match_data = @responder.event_regex.match(@msg)
        @new_due_date = (Time.now + 21 * 86400).strftime("%Y-%m-%d")

        issue_body = "...Reviewers: <!--reviewers-list-->@maelle<!--end-reviewers-list-->" +
                     "<!--due-dates-list-->Due date for @maelle: 2121-12-31<!--end-due-dates-list--> ..."
        allow(@responder).to receive(:issue_body).and_return(issue_body)
      end

      it "should add reviewer and due date in the body of the issue" do
        expected_new_reviewers_list = "@maelle, @xuanxu"
        expected_new_due_dates_list = "Due date for @maelle: 2121-12-31\nDue date for @xuanxu: #{@new_due_date}"
        expect(@responder).to receive(:update_list).with("reviewers", expected_new_reviewers_list)
        expect(@responder).to receive(:update_list).with("due-dates", expected_new_due_dates_list)
        @responder.process_message(@msg)
      end

      it "due date is configurable via settings" do
        @responder.params[:due_date_days] = 10
        due_date = (Time.now + 10 * 86400).strftime("%Y-%m-%d")
        expect(due_date.strip).to_not be_empty
        expect(due_date).to_not eq(@new_due_date)
        expect(@responder).to receive(:respond).with("@xuanxu added to the reviewers list. Review due date is #{due_date}. Thanks @xuanxu for accepting to review!")
        @responder.process_message(@msg)
      end

      it "should respond to github" do
        expect(@responder).to receive(:respond).with("@xuanxu added to the reviewers list. Review due date is #{@new_due_date}. Thanks @xuanxu for accepting to review!")
        @responder.process_message(@msg)
      end

      it "should add data to Airtable" do
        expect(@responder).to receive(:airtable_add_reviewer)
        @responder.process_message('')
      end

      it "should respond with a link to reviewers guide when standard submission-type" do
        issue_body = "...Reviewers: <!--reviewers-list-->@maelle<!--end-reviewers-list-->" +
                     "<!--due-dates-list-->Due date for @maelle: 2121-12-31<!--end-due-dates-list--> ..." +
                     "<!--submission-type-->Standard<!--end-submission-type-->"
        allow(@responder).to receive(:issue_body).and_return(issue_body)

        expect(@responder).to receive(:respond).with("@xuanxu added to the reviewers list. Review due date is #{@new_due_date}. Thanks @xuanxu for accepting to review! Please refer to [our reviewer guide](https://devguide.ropensci.org/reviewerguide.html).")
        @responder.process_message(@msg)
      end

      it "should respond the same for estandar and standard submission types" do
        issue_body = "...Reviewers: <!--reviewers-list-->@maelle<!--end-reviewers-list-->" +
                     "<!--due-dates-list-->Due date for @maelle: 2121-12-31<!--end-due-dates-list--> ..." +
                     "<!--submission-type-->Estándar<!--end-submission-type-->"
        allow(@responder).to receive(:issue_body).and_return(issue_body)

        expect(@responder).to receive(:respond).with("@xuanxu added to the reviewers list. Review due date is #{@new_due_date}. Thanks @xuanxu for accepting to review! Please refer to [our reviewer guide](https://devguide.ropensci.org/reviewerguide.html).")
        @responder.process_message(@msg)
      end

      it "should respond with a link to statistical software reviewers guide when stats submission-type" do
        issue_body = "...Reviewers: <!--reviewers-list-->@maelle<!--end-reviewers-list-->" +
                     "<!--due-dates-list-->Due date for @maelle: 2121-12-31<!--end-due-dates-list--> ..." +
                     "<!--submission-type-->Stats<!--end-submission-type-->"
        allow(@responder).to receive(:issue_body).and_return(issue_body)

        expect(@responder).to receive(:respond).with("@xuanxu added to the reviewers list. Review due date is #{@new_due_date}. Thanks @xuanxu for accepting to review! Please refer to [our reviewer guide](https://ropenscilabs.github.io/statistical-software-review-book/pkgreview.html).")
        @responder.process_message(@msg)
      end

      it "should not add reviewer if already present in the list" do
        msg = "@ropensci-review-bot add @maelle to reviewers"
        @responder.match_data = @responder.event_regex.match(msg)
        expect(@responder).to_not receive(:update_issue)
        expect(@responder).to_not receive(:airtable_add_reviewer)
        expect(@responder).to receive(:respond).with("@maelle is already included in the reviewers list")
        @responder.process_message(msg)
      end

      it "should not add as assignee/collaborator if not configured" do
        expect(@responder).to_not receive(:add_collaborator)
        expect(@responder).to_not receive(:add_assignee)
        @responder.process_message(@msg)
      end

      it "should add as collaborator if configured" do
        @responder.params[:add_as_collaborator] = true
        expect(@responder).to receive(:add_collaborator)
        expect(@responder).to_not receive(:add_assignee)
        @responder.process_message(@msg)
      end

      it "should add as assignee if configured" do
        @responder.params[:add_as_assignee] = true
        expect(@responder).to_not receive(:add_collaborator)
        expect(@responder).to receive(:add_assignee)
        @responder.process_message(@msg)
      end
    end

    describe "removing a reviewer" do
      before do
        @msg = "@ropensci-review-bot remove @maelle from reviewers"
        @responder.match_data = @responder.event_regex.match(@msg)

        issue_body = "...Reviewers: <!--reviewers-list-->@karthik, @maelle<!--end-reviewers-list--> ..." +
                     "<!--due-dates-list-->Due date for @karthik: 2121-11-31\n" +
                     "Due date for @maelle: 2121-12-31<!--end-due-dates-list--> ..."
        allow(@responder).to receive(:issue_body).and_return(issue_body)
      end

      it "should remove reviewer and due date from the body of the issue" do
        expect(@responder).to receive(:update_list).with("reviewers", "@karthik")
        expect(@responder).to receive(:update_list).with("due-dates", "Due date for @karthik: 2121-11-31")
        @responder.process_message(@msg)
      end

      it "should respond to github" do
        expect(@responder).to receive(:respond).with("@maelle removed from the reviewers list!")
        @responder.process_message(@msg)
      end

      it "should remove data from Airtable" do
        expect(@responder).to receive(:airtable_remove_reviewer)
        @responder.process_message('')
      end

      it "should not remove reviewer if not present in the list" do
        msg = "@ropensci-review-bot remove @other_user from reviewers"
        @responder.match_data = @responder.event_regex.match(msg)
        expect(@responder).to_not receive(:update_issue)
        expect(@responder).to_not receive(:airtable_remove_reviewer)
        expect(@responder).to receive(:respond).with("@other_user is not in the reviewers list")
        @responder.process_message(msg)
      end

      it "should not remove as assignee if not configured" do
        expect(@responder).to_not receive(:remove_assignee)
        @responder.process_message(@msg)
      end

      it "should remove as assignee if configured" do
        @responder.params[:add_as_assignee] = true
        expect(@responder).to receive(:remove_assignee)
        @responder.process_message(@msg)
      end
    end

    describe "process labels" do
      describe "adding labels" do
        before do
          @msg = "@ropensci-review-bot add @maelle to reviewers"
          @responder.match_data = @responder.event_regex.match(@msg)
        end

        it "should not happen with less than two reviewers" do
          issue_body = "...Reviewers: <!--reviewers-list--><!--end-reviewers-list--> ..."
          allow(@responder).to receive(:issue_body).and_return(issue_body)

          expect(@responder).to_not receive(:process_labeling)
          expect(@responder).to_not receive(:process_reverse_labeling)

          @responder.process_message(@msg)
        end

        it "should not happen with more than two reviewers" do
          issue_body = "...Reviewers: <!--reviewers-list-->@karthik, @mpadge<!--end-reviewers-list--> ..."
          allow(@responder).to receive(:issue_body).and_return(issue_body)

          expect(@responder).to_not receive(:process_labeling)
          expect(@responder).to_not receive(:process_reverse_labeling)

          @responder.process_message(@msg)
        end

        it "should happen when the second reviewer is assigned" do
          issue_body = "...Reviewers: <!--reviewers-list-->@karthik<!--end-reviewers-list--> ..."
          allow(@responder).to receive(:issue_body).and_return(issue_body)

          expect(@responder).to receive(:process_labeling)
          expect(@responder).to_not receive(:process_reverse_labeling)

          @responder.process_message(@msg)
        end
      end

      describe "removing labels" do
        before do
          @msg = "@ropensci-review-bot remove @maelle from reviewers"
          @responder.match_data = @responder.event_regex.match(@msg)
        end

        it "should not happen with less than two reviewers" do
          issue_body = "...Reviewers: <!--reviewers-list-->@maelle<!--end-reviewers-list--> ..."
          allow(@responder).to receive(:issue_body).and_return(issue_body)

          expect(@responder).to_not receive(:process_reverse_labeling)
          expect(@responder).to_not receive(:process_labeling)

          @responder.process_message(@msg)
        end

        it "should not happen with more than two reviewers" do
          issue_body = "...Reviewers: <!--reviewers-list-->@karthik, @mpadge, @maelle<!--end-reviewers-list--> ..."
          allow(@responder).to receive(:issue_body).and_return(issue_body)

          expect(@responder).to_not receive(:process_reverse_labeling)
          expect(@responder).to_not receive(:process_labeling)

          @responder.process_message(@msg)
        end

        it "should happen when the second reviewer is removed" do
          issue_body = "...Reviewers: <!--reviewers-list-->@karthik, @maelle<!--end-reviewers-list--> ..."
          allow(@responder).to receive(:issue_body).and_return(issue_body)

          expect(@responder).to receive(:process_reverse_labeling)
          expect(@responder).to_not receive(:process_labeling)

          @responder.process_message(@msg)
        end
      end
    end
  end

  describe "#airtable_add_reviewer" do
    before do
      disable_github_calls_for(@responder)
      @responder.context = OpenStruct.new(issue_id: 33,
                                          issue_title: "Bioinfo package",
                                          issue_author: "@uthor",
                                          repo: "openjournals/testing",
                                          sender: "xuanxu")
      allow(@responder).to receive(:reviewer).and_return("@reviewer_21")
      @expected_params = { airtable_token: "1234567890", no_reviewer_text: "TBD" }
      @expected_locals = { bot_name: "ropensci-review-bot",
                           issue_id: 33,
                           repo: "openjournals/testing",
                           sender: "xuanxu",
                           issue_author: "@uthor"}
    end

    it "should pass title to the AirtableWorker when there is no package-name" do
      expected_custom_params = { reviewer: "@reviewer_21", package_name: "Bioinfo package" }

      issue_body = "...Package: <!--package-name--><!--end-package-name--> ..."
      allow(@responder).to receive(:issue_body).and_return(issue_body)

      expect(Ropensci::AirtableWorker).to receive(:perform_async).with(:assign_reviewer,
                                                                       @expected_params,
                                                                       @expected_locals,
                                                                       expected_custom_params)

      @responder.airtable_add_reviewer
    end

    it "should pass package-name to the AirtableWorker" do
      expected_custom_params = { reviewer: "@reviewer_21", package_name: "Superpackage!" }

      issue_body = "...Package: <!--package-name-->Superpackage!<!--end-package-name--> ..."
      allow(@responder).to receive(:issue_body).and_return(issue_body)

      expect(Ropensci::AirtableWorker).to receive(:perform_async).with(:assign_reviewer,
                                                                       @expected_params,
                                                                       @expected_locals,
                                                                       expected_custom_params)

      @responder.airtable_add_reviewer
    end
  end

  describe "#airtable_remove_reviewer" do
    before do
      disable_github_calls_for(@responder)
      @responder.context = OpenStruct.new(issue_id: 33,
                                          issue_title: "Bioinfo package",
                                          issue_author: "@uthor",
                                          repo: "openjournals/testing",
                                          sender: "xuanxu")
      allow(@responder).to receive(:reviewer).and_return("@reviewer_21")
      @expected_params = { airtable_token: "1234567890", no_reviewer_text: "TBD" }
      @expected_locals = { bot_name: "ropensci-review-bot",
                           issue_id: 33,
                           repo: "openjournals/testing",
                           sender: "xuanxu",
                           issue_author: "@uthor"}
    end

    it "should create an AirtableWorker job to remove reviewer" do
      expected_custom_params = { reviewer: "@reviewer_21" }
      expect(Ropensci::AirtableWorker).to receive(:perform_async).with(:remove_reviewer,
                                                                       @expected_params,
                                                                       @expected_locals,
                                                                       expected_custom_params)

      @responder.airtable_remove_reviewer
    end
  end

  describe "#airtable_slack_invites" do
    before do
      disable_github_calls_for(@responder)
      @responder.context = OpenStruct.new(issue_id: 33,
                                          issue_title: "Bioinfo package",
                                          issue_author: "@uthor",
                                          repo: "openjournals/testing",
                                          sender: "xuanxu")
      allow(@responder).to receive(:reviewer).and_return("@reviewer_21")
      @expected_params = { airtable_token: "1234567890", no_reviewer_text: "TBD" }
      @expected_locals = { bot_name: "ropensci-review-bot",
                           issue_id: 33,
                           repo: "openjournals/testing",
                           sender: "xuanxu",
                           issue_author: "@uthor"}
    end

    it "should create an AirtableWorker job to add entries to slack_invites" do
      expected_custom_params = { reviewers: ["rev1", "rev2"], author: "author", author_others: ["other"], package_name: "Bioinfo package" }

      issue_body = "...Package: <!--package-name--><!--end-package-name--> ..." +
                   ".. First author: <!--author1-->@author<!--end-author1--> ..." +
                   ".. Other authors: <!--author-others-->@other<!--end-author-others--> ..."

      allow(@responder).to receive(:issue_body).and_return(issue_body)
      expect(Ropensci::AirtableWorker).to receive(:perform_async).with(:slack_invites,
                                                                       @expected_params,
                                                                       @expected_locals,
                                                                       expected_custom_params)

      @responder.airtable_slack_invites(["@rev1", "rev2"])
    end
  end

  describe "#add_as_collaborator?" do
    it "is false if value is not a username" do
      expect(@responder.username?("not username value")).to be_falsy
      expect(@responder.add_as_collaborator?("not username value")).to be_falsy
    end

    it "is false if param[:add_as_collaborator] is false" do
      expect(@responder.username?("@username")).to be_truthy
      expect(@responder.params[:add_as_collaborator]).to be_falsy
      expect(@responder.add_as_collaborator?("@username")).to be_falsy
    end

    it "is true if value is username and param[:add_as_collaborator] is true" do
      expect(@responder.username?("@username")).to be_truthy
      @responder.params[:add_as_collaborator] = true
      expect(@responder.add_as_collaborator?("@username")).to be_truthy
    end
  end

  describe "#add_as_assignee?" do
    it "is false if value is not a username" do
      expect(@responder.username?("not username value")).to be_falsy
      expect(@responder.add_as_assignee?("not username value")).to be_falsy
    end

    it "is false if param[:add_as_assignee] is false" do
      expect(@responder.username?("@username")).to be_truthy
      expect(@responder.params[:add_as_assignee]).to be_falsy
      expect(@responder.add_as_assignee?("@username")).to be_falsy
    end

    it "is true if value is username and param[:add_as_assignee] is true" do
      expect(@responder.username?("@username")).to be_truthy
      @responder.params[:add_as_assignee] = true
      expect(@responder.add_as_assignee?("@username")).to be_truthy
    end
  end

  describe "#respond_by_submission_type" do
    before do
      @due_date = (Time.now + 21 * 86400).strftime("%Y-%m-%d")
      allow(@responder).to receive(:reviewer).and_return("@rev1")
    end

    it "replies link to ropensci reviewers guide if submission type is Standard" do
      allow(@responder).to receive(:read_value_from_body).with("submission-type").and_return("Standard")
      expect(@responder).to receive(:respond).with(/devguide.ropensci.org\/reviewerguide.html/)
      @responder.respond_by_submission_type
    end

    it "replies link to statistical software reviewers guide if submission type is Stats" do
      allow(@responder).to receive(:read_value_from_body).with("submission-type").and_return("Stats")
      expect(@responder).to receive(:respond).with(/ropenscilabs.github.io\/statistical-software-review-book\/pkgreview.html/)
      @responder.respond_by_submission_type
    end

    it "replies with generic response for unrecognized submission types" do
      allow(@responder).to receive(:read_value_from_body).with("submission-type").and_return("Whatever")
      expect(@responder).to receive(:respond).with("@rev1 added to the reviewers list. Review due date is #{@due_date}. Thanks @rev1 for accepting to review!")
      @responder.respond_by_submission_type
    end

    it "replies with generic response if no submission type" do
      allow(@responder).to receive(:read_value_from_body).with("submission-type").and_return("")
      expect(@responder).to receive(:respond).with("@rev1 added to the reviewers list. Review due date is #{@due_date}. Thanks @rev1 for accepting to review!")
      @responder.respond_by_submission_type
    end
  end

  describe "documentation" do
    it "#description should include adding and removing reviewers" do
      expect(@responder.description[0]).to eq("Add a user to this issue's reviewers list")
      expect(@responder.description[1]).to eq("Remove a user from the reviewers list")
    end

    it "#example_invocation should use custom sample value if present" do
      @responder.params = { sample_value: "@reviewer_username" }
      expect(@responder.example_invocation[0]).to eq("@ropensci-review-bot add @reviewer_username to reviewers")
      expect(@responder.example_invocation[1]).to eq("@ropensci-review-bot remove @reviewer_username from reviewers")
    end

    it "#example_invocation should have default sample value" do
      @responder.params = {}
      expect(@responder.example_invocation[0]).to eq("@ropensci-review-bot add xxxxx to reviewers")
      expect(@responder.example_invocation[1]).to eq("@ropensci-review-bot remove xxxxx from reviewers")
    end
  end

end
