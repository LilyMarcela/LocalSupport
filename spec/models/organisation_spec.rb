require 'spec_helper'

describe Organisation do

  before do
    FactoryGirl.factories.clear
    FactoryGirl.find_definitions

    Geocoder.configure(:lookup => :test)
    Geocoder::Lookup::Test.set_default_stub(
    [
      {
        'latitude' => 40.7143528,
        'longitude' => -74.0059731,
        'address' => 'New York, NY, USA',
        'state' => 'New York',
        'state_code' => 'NY',
        'country' => 'United States',
        'country_code' => 'US'
      }
    ]
    )

    @category1 = FactoryGirl.create(:category, :charity_commission_id => 207)
    @category2 = FactoryGirl.create(:category, :charity_commission_id => 305)
    @category3 = FactoryGirl.create(:category, :charity_commission_id => 108)
    @category4 = FactoryGirl.create(:category, :charity_commission_id => 302)
    @category5 = FactoryGirl.create(:category, :charity_commission_id => 306)
    @org1 = FactoryGirl.build(:organisation, :email => nil, :name => 'Harrow Bereavement Counselling', :description => 'Bereavement Counselling', :address => '64 pinner road', :postcode => 'HA1 3TE', :donation_info => 'www.harrow-bereavment.co.uk/donate')
    @org1.save!
    @org2 = FactoryGirl.build(:organisation, :email => nil,  :name => 'Indian Elders Association',
                              :description => 'Care for the elderly', :address => '62 pinner road', :postcode => 'HA1 3RE', :donation_info => 'www.indian-elders.co.uk/donate')
    @org2.categories << @category1
    @org2.categories << @category2
    @org2.save!
    @org3 = FactoryGirl.build(:organisation, :email => nil, :name => 'Age UK Elderly', :description => 'Care for older people', :address => '62 pinner road', :postcode => 'HA1 3RE', :donation_info => 'www.age-uk.co.uk/donate')
    @org3.categories << @category1
    @org3.save!
  end
  describe "#not_updated_recently_or_has_no_owner?" do
    let(:subject){FactoryGirl.create(:organisation, :name => "Org with no owner", :updated_at => 364.day.ago)}
    context 'has no owner but updated recently' do
      it{expect(subject.not_updated_recently_or_has_no_owner?).to be_true}
    end
    context 'has owner but old update' do
      let(:subject){FactoryGirl.create(:organisation_with_owner, :updated_at => 366.day.ago)}
      it{expect(subject.not_updated_recently_or_has_no_owner?).to be_true}
    end
    context 'has no owner and old update' do 
      let(:subject){FactoryGirl.create(:organisation, :updated_at => 366.day.ago)}
      it{expect(subject.not_updated_recently_or_has_no_owner?).to be_true}
    end
    context 'has owner and recent update' do
      let(:subject){FactoryGirl.create(:organisation_with_owner, :updated_at => 364.day.ago)}
      it{expect(subject.not_updated_recently_or_has_no_owner?).to be_false}
    end
  end

  describe "#gmaps4rails_marker_picture" do

    context 'no user' do
      it 'returns small icon when no associated user' do
        expect(@org1.gmaps4rails_marker_picture).to eq({"picture" => "https://maps.gstatic.com/intl/en_ALL/mapfiles/markers2/measle.png"})
      end
    end

    context 'has user' do
      before(:each) do
        usr = FactoryGirl.create(:user, :email => "orgadmin@org.org")
        usr.confirm!
        @org1.users << [usr]
        @org1.save!
      end
      after(:each) do
        allow(Time).to receive(:now).and_call_original
      end
      it 'returns large icon when there is an associated user' do
        expect(@org1.gmaps4rails_marker_picture).to eq({})
      end

      [365, 366, 500].each do |days|
        it "returns small icon when update is #{days} days old" do
          future_time = Time.at(Time.now + days.day)
          Time.stub(:now){future_time}
          expect(@org1.gmaps4rails_marker_picture).to eq({"picture" => "https://maps.gstatic.com/intl/en_ALL/mapfiles/markers2/measle.png"})
        end
      end
      [ 2, 100, 200, 364].each do |days|
        it "returns large icon when update is only #{days} days old" do
          future_time = Time.at(Time.now + days.day)
          Time.stub(:now){future_time}
          expect(@org1.gmaps4rails_marker_picture).to eq({})
        end
      end
    end
  end
  context 'scopes for orphan orgs' do
    before(:each) do
      @user = FactoryGirl.create(:user, :email => "hello@hello.com")
      @user.confirm!
    end

    it 'should allow us to grab orgs with emails' do
      Organisation.not_null_email.should eq []
      @org1.email = "hello@hello.com"
      @org1.save
      Organisation.not_null_email.should eq [@org1]
    end

    it 'should allow us to grab orgs with no admin' do
      Organisation.null_users.sort.should eq [@org1, @org2, @org3].sort
      @org1.email = "hello@hello.com"
      @org1.save
      @user.confirm!
      @org1.users.should eq [@user]
      Organisation.null_users.sort.should eq [@org2, @org3].sort
    end

    it 'should allow us to exclude previously invited users' do
      @org1.email = "hello@hello.com"
      @org1.save
      Organisation.without_matching_user_emails.should_not include @org1
    end

    # Should we have more tests to cover more possible combinations?
    it 'should allow us to combine scopes' do
      @org1.email = "hello@hello.com"
      @org1.save
      @org3.email = "hello_again@you_again.com"
      @org3.save
      Organisation.null_users.not_null_email.sort.should eq [@org1, @org3]
      Organisation.null_users.not_null_email.without_matching_user_emails.sort.should eq [@org3]
    end
  end

  context 'validating URLs' do
    subject(:no_http_org) { FactoryGirl.build(:organisation, :name => 'Harrow Bereavement Counselling', :description => 'Bereavement Counselling', :address => '64 pinner road', :postcode => 'HA1 3TE', :donation_info => 'www.harrow-bereavment.co.uk/donate') }
    subject(:empty_website)  {FactoryGirl.build(:organisation, :name => 'Harrow Bereavement Counselling', :description => 'Bereavement Counselling', :address => '64 pinner road', :postcode => 'HA1 3TE', :donation_info => '', :website => '')}
    it 'if lacking protocol, http is prefixed to URL when saved' do
      no_http_org.save!
      no_http_org.donation_info.should include('http://')
    end

    it 'a URL is left blank, no validation issues arise' do
      expect {no_http_org.save! }.to_not raise_error
    end

    it 'does not raise validation issues when URLs are empty strings' do
      expect {empty_website.save!}.to_not raise_error
    end
  end

  context 'adding charity admins by email' do
    it 'handles a non-existent email with an error' do
      expect(@org1.update_attributes_with_admin({:admin_email_to_add => 'nonexistentuser@example.com'})).to be_false
      expect(@org1.errors[:administrator_email]).to eq ["The user email you entered,'nonexistentuser@example.com', does not exist in the system"]
    end
    it 'does not update other attributes when there is a non-existent email' do
      expect(@org1.update_attributes_with_admin({:name => 'New name',:admin_email_to_add => 'nonexistentuser@example.com'})).to be_false
      expect(@org1.name).not_to eq 'New name'
    end
    it 'handles a nil email' do
      expect(@org1.update_attributes_with_admin({:admin_email_to_add => nil})).to be_true
      expect(@org1.errors.any?).to be_false
    end
    it 'handles a blank email' do
      expect(@org1.update_attributes_with_admin({:admin_email_to_add => ''})).to be_true
      expect(@org1.errors.any?).to be_false
    end
    it 'adds existent user as charity admin' do
      usr = FactoryGirl.create(:user, :email => 'user@example.org')
      expect(@org1.update_attributes_with_admin({:admin_email_to_add => usr.email})).to be_true
      expect(@org1.users).to include usr
    end
    it 'updates other attributes with blank email' do
      expect(@org1.update_attributes_with_admin({:name => 'New name',:admin_email_to_add => ''})).to be_true
      expect(@org1.name).to eq 'New name'
    end
    it 'updates other attributes with valid email' do
      usr = FactoryGirl.create(:user, :email => 'user@example.org')
      expect(@org1.update_attributes_with_admin({:name => 'New name',:admin_email_to_add => usr.email})).to be_true
      expect(@org1.name).to eq 'New name'
    end
  end
  it 'responds to filter by category' do
    expect(Organisation).to respond_to(:filter_by_category)
  end

  it 'finds all orgs in a particular category' do
    expect(Organisation.filter_by_category(@category1.id)).not_to include @org1
    expect(Organisation.filter_by_category(@category1.id)).to include @org2
    expect(Organisation.filter_by_category(@category1.id)).to include @org3
  end

  it 'finds all orgs when category is nil' do
    expect(Organisation.filter_by_category(nil)).to include(@org1)
    expect(Organisation.filter_by_category(nil)).to include(@org2)
    expect(Organisation.filter_by_category(nil)).to include(@org3)
  end

  it 'should have and belong to many categories' do
    expect(@org2.categories).to include(@category1)
    expect(@org2.categories).to include(@category2)
  end

  it 'must have search by keyword' do
    expect(Organisation).to respond_to(:search_by_keyword)
  end

  it 'find all orgs that have keyword anywhere in their name or description' do
    expect(Organisation.search_by_keyword("elderly")).to eq([@org2, @org3])
  end

  it 'searches by keyword and filters by category and has zero results' do
    result = Organisation.search_by_keyword("Harrow").filter_by_category("1")
    expect(result).not_to include @org1, @org2, @org3
  end

  it 'searches by keyword and filters by category and has results' do
    result = Organisation.search_by_keyword("Indian").filter_by_category(@category1.id)
    expect(result).to include @org2
    expect(result).not_to include @org1, @org3
  end

  it 'searches by keyword when filter by category id is nil' do
    result = Organisation.search_by_keyword("Harrow").filter_by_category(nil)
    expect(result).to include @org1
    expect(result).not_to include @org2, @org3
  end

  it 'filters by category when searches by keyword is nil' do
    result = Organisation.search_by_keyword(nil).filter_by_category(@category1.id)
    expect(result).to include @org2, @org3
    expect(result).not_to include @org1
  end

  it 'returns all orgs when both filter by category and search by keyword are nil args' do
    result = Organisation.search_by_keyword(nil).filter_by_category(nil)
    expect(result).to include @org1, @org2, @org3
  end

  it 'handles weird input (possibly from infinite scroll system)' do
    # Couldn't find Category with id=?test=0
    expect(lambda {Organisation.filter_by_category("?test=0")} ).not_to raise_error
  end

  it 'has users' do
    expect(@org1).to respond_to(:users)
  end

  it 'can humanize with all first capitals' do
    expect("HARROW BAPTIST CHURCH, COLLEGE ROAD, HARROW".humanized_all_first_capitals).to eq("Harrow Baptist Church, College Road, Harrow")
  end

  describe 'Creating of Organisations from CSV file' do
    before(:all){ @headers = 'Title,Charity Number,Activities,Contact Name,Contact Address,website,Contact Telephone,date registered,date removed,accounts date,spending,income,company number,OpenlyLocalURL,twitter account name,facebook account name,youtube account name,feed url,Charity Classification,signed up for 1010,last checked,created at,updated at,Removed?'.split(',')}

    it 'must not override an existing organisation' do
      fields = CSV.parse('INDIAN ELDERS ASSOCIATION,1129832,NO INFORMATION RECORDED,MR JOHN ROSS NEWBY,"HARROW BAPTIST CHURCH,COLLEGE ROAD, HARROW, HA1 1BA",http://www.harrow-baptist.org.uk,020 8863 7837,2009-05-27,,,,,,http://OpenlyLocal.com/charities/57879-HARROW-BAPTIST-CHURCH,,,,,"207,305,108,302,306",false,2010-09-20T21:38:52+01:00,2010-08-22T22:19:07+01:00,2012-04-15T11:22:12+01:00,*****')
      org = create_organisation(fields)
      expect(org).to be_nil
    end

    it 'must not create org when date removed is not nil' do
      fields = CSV.parse('HARROW BAPTIST CHURCH,1129832,NO INFORMATION RECORDED,MR JOHN ROSS NEWBY,"HARROW BAPTIST CHURCH, COLLEGE ROAD, HARROW",http://www.harrow-baptist.org.uk,020 8863 7837,2009-05-27,2009-05-28,,,,,http://OpenlyLocal.com/charities/57879-HARROW-BAPTIST-CHURCH,,,,,"207,305,108,302,306",false,2010-09-20T21:38:52+01:00,2010-08-22T22:19:07+01:00,2012-04-15T11:22:12+01:00,*****')
      org = create_organisation(fields)
      expect(org).to be_nil
    end

    # the following 6 or so feel more like integration tests than unit tests
    # TODO should they be moved into another file?  OR MAYBE TO CUCUMBER???
    it 'must be able to generate multiple Organisations from text file' do
      mock_org = double("org")
      [:name, :name=, :description=, :address=, :postcode=, :website=, :telephone=].each do |method|
        mock_org.stub(method)
      end
      Organisation.stub(:find_by_name).and_return nil
      attempted_number_to_import = 1006
      actual_number_to_import = 642
      time = Time.now
      Organisation.should_receive(:new).exactly(actual_number_to_import).and_return mock_org
      rows_to_parse = (1..attempted_number_to_import).collect do |number|
          hash_to_return = {}
          hash_to_return.stub(:header?){true}
          hash_to_return[Organisation.column_mappings[:name]] = "Test org #{number}"
          hash_to_return[Organisation.column_mappings[:address]] = "10 Downing St London SW1A 2AA, United Kingdom"
        if(actual_number_to_import < number)
           hash_to_return[Organisation.column_mappings[:date_removed]] = time
        end

        hash_to_return
      end
      mock_file_handle = double("file")
      File.should_receive(:open).and_return(mock_file_handle)
      CSV.should_receive(:parse).with(mock_file_handle, :headers => true).and_return rows_to_parse
      mock_org.should_receive(:save!).exactly(actual_number_to_import)
      Organisation.import_addresses 'db/data.csv', attempted_number_to_import

    end

    it 'must fail gracefully when encountering error in generating multiple Organisations from text file' do
      attempted_number_to_import = 1006
      actual_number_to_import = 642
      Organisation.stub(:create_from_array).and_raise(CSV::MalformedCSVError)
      expect(lambda {
        Organisation.import_addresses 'db/data.csv', attempted_number_to_import
      }).to change(Organisation, :count).by(0)
    end

    it 'must be able to handle no postcode in text representation' do
      fields = CSV.parse('HARROW BAPTIST CHURCH,1129832,NO INFORMATION RECORDED,MR JOHN ROSS NEWBY,"HARROW BAPTIST CHURCH, COLLEGE ROAD, HARROW",http://www.harrow-baptist.org.uk,020 8863 7837,2009-05-27,,,,,,http://OpenlyLocal.com/charities/57879-HARROW-BAPTIST-CHURCH,,,,,"207,305,108,302,306",false,2010-09-20T21:38:52+01:00,2010-08-22T22:19:07+01:00,2012-04-15T11:22:12+01:00,*****')
      org = create_organisation(fields)
      expect(org.name).to eq('Harrow Baptist Church')
      expect(org.description).to eq('No information recorded')
      expect(org.address).to eq('Harrow Baptist Church, College Road, Harrow')
      expect(org.postcode).to eq('')
      expect(org.website).to eq('http://www.harrow-baptist.org.uk')
      expect(org.telephone).to eq('020 8863 7837')
      expect(org.donation_info).to eq(nil)
    end

    it 'must be able to handle no address in text representation' do
      fields = CSV.parse('HARROW BAPTIST CHURCH,1129832,NO INFORMATION RECORDED,MR JOHN ROSS NEWBY,,http://www.harrow-baptist.org.uk,020 8863 7837,2009-05-27,,,,,,http://OpenlyLocal.com/charities/57879-HARROW-BAPTIST-CHURCH,,,,,"207,305,108,302,306",false,2010-09-20T21:38:52+01:00,2010-08-22T22:19:07+01:00,2012-04-15T11:22:12+01:00,*****')
      org = create_organisation(fields)
      expect(org.name).to eq('Harrow Baptist Church')
      expect(org.description).to eq('No information recorded')
      expect(org.address).to eq('')
      expect(org.postcode).to eq('')
      expect(org.website).to eq('http://www.harrow-baptist.org.uk')
      expect(org.telephone).to eq('020 8863 7837')
      expect(org.donation_info).to eq(nil)
    end

    it 'must be able to generate Organisation from text representation ensuring words in correct case and postcode is extracted from address' do
      fields = CSV.parse('HARROW BAPTIST CHURCH,1129832,NO INFORMATION RECORDED,MR JOHN ROSS NEWBY,"HARROW BAPTIST CHURCH, COLLEGE ROAD, HARROW, HA1 1BA",http://www.harrow-baptist.org.uk,020 8863 7837,2009-05-27,,,,,,http://OpenlyLocal.com/charities/57879-HARROW-BAPTIST-CHURCH,,,,,"207,305,108,302,306",false,2010-09-20T21:38:52+01:00,2010-08-22T22:19:07+01:00,2012-04-15T11:22:12+01:00,*****')
      org = create_organisation(fields)
      expect(org.name).to eq('Harrow Baptist Church')
      expect(org.description).to eq('No information recorded')
      expect(org.address).to eq('Harrow Baptist Church, College Road, Harrow')
      expect(org.postcode).to eq('HA1 1BA')
      expect(org.website).to eq('http://www.harrow-baptist.org.uk')
      expect(org.telephone).to eq('020 8863 7837')
      expect(org.donation_info).to eq(nil)
    end


    it 'should raise error if no columns found' do
      #Headers are without Title header
      @headers = 'Charity Number,Activities,Contact Name,Contact Address,website,Contact Telephone,date registered,date removed,accounts date,spending,income,company number,OpenlyLocalURL,twitter account name,facebook account name,youtube account name,feed url,Charity Classification,signed up for 1010,last checked,created at,updated at,Removed?'.split(',')
      fields = CSV.parse('HARROW BAPTIST CHURCH,1129832,NO INFORMATION RECORDED,MR JOHN ROSS NEWBY,"HARROW BAPTIST CHURCH, COLLEGE ROAD, HARROW, HA1 1BA",http://www.harrow-baptist.org.uk,020 8863 7837,2009-05-27,,,,,,http://OpenlyLocal.com/charities/57879-HARROW-BAPTIST-CHURCH,,,,,"207,305,108,302,306",false,2010-09-20T21:38:52+01:00,2010-08-22T22:19:07+01:00,2012-04-15T11:22:12+01:00,*****')
      expect(lambda{
        org = create_organisation(fields)
      }).to raise_error
    end


    def create_organisation(fields)
      row = CSV::Row.new(@headers, fields.flatten)
      Organisation.create_from_array(row, true)
    end

    context "importing category relations" do
      let(:fields) do
        CSV.parse('HARROW BEREAVEMENT COUNSELLING,1129832,NO INFORMATION RECORDED,MR JOHN ROSS NEWBY,"HARROW BAPTIST CHURCH, COLLEGE ROAD, HARROW, HA1 1BA",http://www.harrow-baptist.org.uk,020 8863 7837,2009-05-27,,,,,,http://OpenlyLocal.com/charities/57879-HARROW-BAPTIST-CHURCH,,,,,"207,305,108,302,306",false,2010-09-20T21:38:52+01:00,2010-08-22T22:19:07+01:00,2012-04-15T11:22:12+01:00,*****')
      end
      let(:row) do
        CSV::Row.new(@headers, fields.flatten)
      end
      let(:fields_cat_missing) do
        CSV.parse('HARROW BEREAVEMENT COUNSELLING,1129832,NO INFORMATION RECORDED,MR JOHN ROSS NEWBY,"HARROW BAPTIST CHURCH, COLLEGE ROAD, HARROW, HA1 1BA",http://www.harrow-baptist.org.uk,020 8863 7837,2009-05-27,,,,,,http://OpenlyLocal.com/charities/57879-HARROW-BAPTIST-CHURCH,,,,,,false,2010-09-20T21:38:52+01:00,2010-08-22T22:19:07+01:00,2012-04-15T11:22:12+01:00,*****')
      end
      let(:row_cat_missing) do
        CSV::Row.new(@headers, fields_cat_missing.flatten)
      end
      it 'must be able to avoid org category relations from text file when org does not exist' do
        @org4 = FactoryGirl.build(:organisation, :name => 'Fellowship For Management In Food Distribution', :description => 'Bereavement Counselling', :address => '64 pinner road', :postcode => 'HA1 3TE', :donation_info => 'www.harrow-bereavment.co.uk/donate')
        @org4.save!
        [102,206,302].each do |id|
          FactoryGirl.build(:category, :charity_commission_id => id).save!
        end
        attempted_number_to_import = 2
        number_cat_org_relations_generated = 3
        expect(lambda {
          Organisation.import_category_mappings 'db/data.csv', attempted_number_to_import
        }).to change(CategoryOrganisation, :count).by(number_cat_org_relations_generated)
      end

      it "allows us to import categories" do
        org = Organisation.import_categories_from_array(row)
        expect(org.categories.length).to eq 5
        [207,305,108,302,306].each do |id|
          expect(org.categories).to include(Category.find_by_charity_commission_id(id))
        end
      end

      it 'must fail gracefully when encountering error in importing categories from text file' do
        attempted_number_to_import = 2
        Organisation.stub(:import_categories_from_array).and_raise(CSV::MalformedCSVError)
        expect(lambda {
          Organisation.import_category_mappings 'db/data.csv', attempted_number_to_import
        }).to change(Organisation, :count).by(0)
      end

      it "should import categories when matching org is found" do
        Organisation.should_receive(:check_columns_in).with(row)
        Organisation.should_receive(:find_by_name).with('Harrow Bereavement Counselling').and_return @org1
        array = double('Array')
        [{:cc_id => 207, :cat => @cat1}, {:cc_id => 305, :cat => @cat2}, {:cc_id => 108, :cat => @cat3},
         {:cc_id => 302, :cat => @cat4}, {:cc_id => 306, :cat => @cat5}]. each do |cat_hash|
          Category.should_receive(:find_by_charity_commission_id).with(cat_hash[:cc_id]).and_return(cat_hash[:cat])
          array.should_receive(:<<).with(cat_hash[:cat])
        end
        @org1.should_receive(:categories).exactly(5).times.and_return(array)
        org = Organisation.import_categories_from_array(row)
        expect(org).not_to be_nil
      end

      it "should not import categories when no matching organisation" do
        Organisation.should_receive(:check_columns_in).with(row)
        Organisation.should_receive(:find_by_name).with('Harrow Bereavement Counselling').and_return nil
        org = Organisation.import_categories_from_array(row)
        expect(org).to be_nil
      end

      it "should not import categories when none are listed" do
        Organisation.should_receive(:check_columns_in).with(row_cat_missing)
        Organisation.should_receive(:find_by_name).with('Harrow Bereavement Counselling').and_return @org1
        org = Organisation.import_categories_from_array(row_cat_missing)
        expect(org).not_to be_nil
      end
    end
  end


  it 'should geocode when address changes' do
    new_address = '60 pinner road'
    @org1.should_receive(:geocode)
    @org1.update_attributes :address => new_address
  end

  it 'should geocode when new object is created' do
    address = '60 pinner road'
    postcode = 'HA1 3RE'
    org = FactoryGirl.build(:organisation,:address => address, :postcode => postcode, :name => 'Happy and Nice', :gmaps => true)
    org.should_receive(:geocode)    
    org.save
  end
  
  # not sure if we need SQL injection security tests like this ...
  # org = Organisation.new(:address =>"blah", :gmaps=> ";DROP DATABASE;")
  # org = Organisation.new(:address =>"blah", :name=> ";DROP DATABASE;")

  describe "importing emails" do
    it "should have a method import_emails" do
      Organisation.should_receive(:add_email)
      Organisation.should_receive(:import).with(nil,2,false) do |&arg|
        Organisation.add_email(&arg)
      end
      Organisation.import_emails(nil,2,false)
    end

    it 'should handle absence of org gracefully' do
      Organisation.should_receive(:where).with("UPPER(name) LIKE ? ", "%I LOVE PEOPLE%").and_return(nil)
      expect(lambda{
        response = Organisation.add_email(fields = CSV.parse('i love people,,,,,,,test@example.org')[0],true)
        response.should eq "i love people was not found\n"
      }).not_to raise_error
    end

    it "should add email to org" do
      Organisation.should_receive(:where).with("UPPER(name) LIKE ? ", "%FRIENDLY%").and_return([@org1])
      @org1.should_receive(:email=).with('test@example.org')
      @org1.should_receive(:save)
      Organisation.add_email(fields = CSV.parse('friendly,,,,,,,test@example.org')[0],true)
    end

    it "should add email to org even with case mismatch" do
      Organisation.should_receive(:where).with("UPPER(name) LIKE ? ", "%FRIENDLY%").and_return([@org1])
      @org1.should_receive(:email=).with('test@example.org')
      @org1.should_receive(:save)
      Organisation.add_email(fields = CSV.parse('friendly,,,,,,,test@example.org')[0],true)
    end

    it 'should not add email to org when it has an existing email' do
      @org1.email = 'something@example.com'
      @org1.save!
      Organisation.should_receive(:where).with("UPPER(name) LIKE ? ", "%FRIENDLY%").and_return([@org1])
      @org1.should_not_receive(:email=).with('test@example.org')
      @org1.should_not_receive(:save)
      Organisation.add_email(fields = CSV.parse('friendly,,,,,,,test@example.org')[0],true)
    end
  end

  describe '#generate_potential_user' do
    let(:org) { @org1 }
    # using a stub_model confuses User.should_receive on line 450 because it's expecting :new from my organisation.rb, but instead the stub_model calls it first
    let(:user) { double('User', {:email => org.email, :password => 'password'}) }

    before :each do
      Devise.stub_chain(:friendly_token, :first).with().with(8).and_return('password')
      User.should_receive(:new).with({:email => org.email, :password => 'password'}).and_return(user)
    end

    it 'early returns a (broken) user when the user is invalid' do
      user.should_receive(:valid?).and_return(false)
      user.should_receive(:save)
    end

    it 'returns a user' do
      user.should_receive(:valid?).and_return(true)
      user.should_receive(:skip_confirmation_notification!)
      User.should_receive(:reset_password_token)
      user.should_receive(:reset_password_token=)
      user.should_receive(:reset_password_sent_at=)
      user.should_receive(:save!)
      user.should_receive(:confirm!)
    end

    after(:each) do
      org.generate_potential_user.should eq(user)
    end
  end

  describe 'destroy uses acts_as_paranoid' do
    it 'can be recovered' do
      @org1.destroy
      expect(Organisation.find_by_name('Harrow Bereavement Counselling')).to eq nil
      Organisation.with_deleted.find_by_name('Harrow Bereavement Counselling').restore
      expect(Organisation.find_by_name('Harrow Bereavement Counselling')).to eq @org1
    end
  end

  describe '#uninvite_users' do
    let!(:current_user) { FactoryGirl.create(:user, email: 'admin@example.com', admin: true) }
    let(:org) { FactoryGirl.create :organisation, email: 'YES@hello.com' }
    let(:params) do
      {invite_list: {org.id => org.email,
                     org.id+1 => org.email},
                     resend_invitation: false}
    end
    let(:invited_user) { User.where("users.organisation_id IS NOT null").first }

    before do
      BatchInviteJob.new(params, current_user).run
      expect(invited_user.organisation_id).to eq org.id
    end

    it "unsets user-organisation association of users of the organisation that"\
       "are invited_not_accepted" do
      expect{
        org.uninvite_users
        invited_user.reload
      }.to change(invited_user, :organisation_id).from(org.id).to(nil)
    end

    it "happens when email is updated" do
      expect{
        org.update_attributes(email: 'hello@email.com')
        invited_user.reload
      }.to change(invited_user, :organisation_id).from(org.id).to(nil)
    end

    it "doesn't happen when other attributes are updated" do
      expect{
        org.update_attributes(website: 'www.abc.com')
        invited_user.reload
      }.not_to change(invited_user, :organisation_id)
    end
  end

  context "geocoding" do
    describe 'not_geocoded?' do
      it 'should return true if it lacks latitude and longitude' do
        @org1.assign_attributes(latitude: nil, longitude: nil)
        @org1.not_geocoded?.should be_true
      end

      it 'should return false if it has latitude and longitude' do
        @org2.not_geocoded?.should be_false
      end
    end

    describe 'run_geocode?' do
      it 'should return true if address is changed' do
        @org1.address = "asjkdhas,ba,asda"
        @org1.run_geocode?.should be_true
      end

      it 'should return false if address is not changed' do
        @org1.should_receive(:address_changed?).and_return(false)
        @org1.should_receive(:not_geocoded?).and_return(false)
        @org1.run_geocode?.should be_false
      end

      it 'should return false if org has no address' do
        org = Organisation.new
        org.run_geocode?.should be_false
      end

      it 'should return true if org has an address but no coordinates' do
        @org1.should_receive(:not_geocoded?).and_return(true)
        @org1.run_geocode?.should be_true
      end

      it 'should return false if org has an address and coordinates' do
        @org2.should_receive(:not_geocoded?).and_return(false)
        @org2.run_geocode?.should be_false
      end
    end

    describe "acts_as_gmappable's behavior is curtailed by the { :process_geocoding => :run_geocode? } option" do
      it 'no geocoding allowed when saving if the org already has an address and coordinates' do
        expect_any_instance_of(Organisation).not_to receive(:geocode)
        @org2.email = 'something@example.com'
        @org2.save!
      end

      # it will try to rerun incomplete geocodes, but not valid ones, so no harm is done
      it 'geocoding allowed when saving if the org has an address BUT NO coordinates' do
        expect_any_instance_of(Organisation).to receive(:geocode)
        @org2.longitude = nil ; @org2.latitude = nil
        @org2.email = 'something@example.com'
        @org2.save!
      end

      it 'geocoding allowed when saving if the org address changed' do
        expect_any_instance_of(Organisation).to receive(:geocode)
        @org2.address = '777 pinner road'
        @org2.save!
      end
    end
  end
end