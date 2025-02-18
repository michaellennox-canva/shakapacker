require "pathname"
require "rake"
require "json"
require "shakapacker/utils/misc"
require "shakapacker/utils/version_syntax_converter"

GEM_ROOT = Pathname.new(File.expand_path("../../..", __FILE__))
SPEC_PATH = Pathname.new(File.expand_path("../", __FILE__))
BASE_RAILS_APP_PATH = SPEC_PATH.join("base-rails-app")
TEMP_RAILS_APP_PATH = SPEC_PATH.join("temp-rails-app")

describe "Generator" do
  before :all do
    # Don't use --skip-git because we want .gitignore file to exist in the project
    sh_in_dir(SPEC_PATH, %(
      rails new base-rails-app --skip-javascript --skip-bundle --skip-spring
      rm -rf base-rails-app/.git
    ))

    Bundler.with_unbundled_env do
      sh_in_dir(BASE_RAILS_APP_PATH, %(
        gem update bundler
        bundle add shakapacker --path "#{GEM_ROOT}"
      ))
    end
  end

  after :all do
    Dir.chdir(SPEC_PATH)
    FileUtils.rm_rf(BASE_RAILS_APP_PATH)
  end

  describe "shakapacker:install" do
    context "in a normal Rails project" do
      before :all do
        sh_in_dir(SPEC_PATH, "cp -r '#{BASE_RAILS_APP_PATH}' '#{TEMP_RAILS_APP_PATH}'")

        Bundler.with_unbundled_env do
          sh_in_dir(TEMP_RAILS_APP_PATH, "FORCE=true bundle exec rails shakapacker:install")
        end
      end

      after :all do
        Dir.chdir(SPEC_PATH)
        FileUtils.rm_rf(TEMP_RAILS_APP_PATH)
      end

      it "creates `config/shakapacker.yml`" do
        config_file_relative_path = "config/shakapacker.yml"
        actual_content = read(path_in_the_app(config_file_relative_path))
        expected_content = read(path_in_the_gem(config_file_relative_path))

        expect(actual_content).to eq expected_content
      end

      it "replaces package.json with template file" do
        actual_content = read(path_in_the_app("package.json"))

        expect(actual_content).to match /"name": "app",/
      end

      it "creates webpack config directory and its files" do
        expected_files = [
          "webpack.config.js"
        ]

        Dir.chdir(path_in_the_app("config/webpack")) do
          exisiting_files_in_config_webpack_dir = Dir.glob("*")
          expect(exisiting_files_in_config_webpack_dir).to eq expected_files
        end
      end

      it "adds binstubs" do
        expected_binstubs = []
        Dir.chdir(File.join(GEM_ROOT, "lib/install/bin")) do
          expected_binstubs = Dir.glob("bin/*")
        end

        Dir.chdir(File.join(TEMP_RAILS_APP_PATH, "bin")) do
          actual_binstubs = Dir.glob("*")
          expect(actual_binstubs).to include(*expected_binstubs)
        end
      end

      it "modifies .gitignore" do
        actual_content = read(path_in_the_app(".gitignore"))

        expect(actual_content).to match ".yarn-integrity"
      end

      it 'adds <%= javascript_pack_tag "application" %>' do
        actual_content = read(path_in_the_app("app/views/layouts/application.html.erb"))

        expect(actual_content).to match '<%= javascript_pack_tag "application" %>'
      end

      it "updates `bin/setup" do
        setup_file_content = read(path_in_the_app("bin/setup"))
        expect(setup_file_content).to match %r(^\s*system!\(['"]bin/yarn['"]\))
      end

      it "adds relevant shakapacker version in package.json depending on gem version," do
        npm_version = Shakapacker::Utils::VersionSyntaxConverter.new.rubygem_to_npm(Shakapacker::VERSION)

        actual_content = read(path_in_the_app("package.json"))

        expect(actual_content).to match /"shakapacker": "#{npm_version}",/
      end

      it "adds Shakapacker peer dependencies to package.json" do
        package_json = JSON.parse(File.read(path_in_the_app("package.json")))
        actual_dependencies = package_json["dependencies"]&.keys

        expected_dependencies = %w(
          @babel/core
          @babel/plugin-transform-runtime
          @babel/preset-env
          @babel/runtime
          babel-loader
          compression-webpack-plugin
          terser-webpack-plugin
          webpack
          webpack-assets-manifest
          webpack-cli
          webpack-merge
        )

        expect(actual_dependencies).to include(*expected_dependencies)
      end

      it "adds Shakapacker peer dev dependencies to package.json" do
        package_json = JSON.parse(File.read(path_in_the_app("package.json")))
        actual_dev_dependencies = package_json["devDependencies"]&.keys

        expected_dev_dependencies = %w(
          webpack-dev-server
        )

        expect(actual_dev_dependencies).to include(*expected_dev_dependencies)
      end

      context "with a basic react app setup" do
        it "passes the test for rendering react component on the page" do
          Bundler.with_unbundled_env do
            sh_in_dir(TEMP_RAILS_APP_PATH, "./bin/rails app:template LOCATION=../e2e_template/template.rb")
            expect(sh_in_dir(TEMP_RAILS_APP_PATH, "bundle exec rspec")).to be_truthy
          end
        end
      end
    end
  end

  private
    def path_in_the_app(relative_path = nil)
      Pathname.new(File.join([TEMP_RAILS_APP_PATH, relative_path].compact))
    end

    def path_in_the_gem(relative_path = nil)
      Pathname.new(File.join([GEM_ROOT, "lib/install" , relative_path].compact))
    end

    def read(path)
      File.read(path)
    end

    def sh_in_dir(dir, *shell_commands)
      Shakapacker::Utils::Misc.sh_in_dir(dir, *shell_commands)
    end
end
