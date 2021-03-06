require 'spec_helper'

module ZK::ZKEventMachine
  shared_examples_for 'Client' do
    include EventedSpec::SpecHelper
    default_timeout 2.0

    let(:base_path) { '/zk-em-testing' }

    before do
      @zk.rm_rf(base_path)
      @zk.mkdir_p(base_path)
    end

    after do
      @zk.rm_rf(base_path)
      @zk.close!
    end

    def event_mock(name=:event)
      flexmock(name).tap do |ev|
        ev.should_receive(:node_event?).and_return(false)
        ev.should_receive(:state_event?).and_return(true)
        ev.should_receive(:session_event?).and_return(true)
        ev.should_receive(:zk=).with_any_args
        yield ev if block_given?
      end
    end

    describe 'connect' do
      it %[should return a deferred that fires when connected and then close] do
        em do
          @zkem.connect do
            true.should be_true
            @zkem.close! do 
              logger.debug { "calling done" }
              done
            end
          end
        end
      end

      it %[should be able to be called mulitple times] do
        em do
          @zkem.connect do
            logger.debug { "inside first callback" }
            @zkem.connect do
              logger.debug { "inside second callback" }
              true.should be_true
              @zkem.close! { done }
            end
          end
        end
      end
    end

    describe 'get' do
      describe 'success' do
        before do
          @path = [base_path, 'foo'].join('/')
          @data = 'this is data'
          @zk.create(@path, @data)
        end

        it 'should get the data and call the callback' do
          em do
            @zkem.connect do
              dfr = @zkem.get(@path)

              dfr.callback do |*a| 
                logger.debug { "got callback with #{a.inspect}" }
                a.should_not be_empty
                a.first.should == @data
                a.last.should be_instance_of(Zookeeper::Stat)
                EM.reactor_thread?.should be_true
                @zkem.close! { done }
              end

              dfr.errback  do |exc| 
                raise exc
              end
            end
          end
        end

        it 'should get the data and do a nodejs-style callback' do
          em do
            @zkem.connect do
              @zkem.get(@path) do |exc,data,stat|
                exc.should be_nil
                data.should == @data
                stat.should be_instance_of(Zookeeper::Stat)
                EM.reactor_thread?.should be_true
                @zkem.close! { done }
              end
            end
          end
        end
      end # success

      describe 'failure' do
        before do
          @path = [base_path, 'foo'].join('/')
          @zk.delete(@path) rescue ZK::Exceptions::NoNode
        end

        it %[should call the errback in deferred style] do
          em do
            @zkem.connect do
              d = @zkem.get(@path)

              d.callback do
                raise "Should not have been called"
              end

              d.errback do |exc|
                exc.should be_kind_of(ZK::Exceptions::NoNode)
                logger.debug { "calling done" }
                @zkem.close! { done }
              end
            end
          end
        end

        it %[should have NoNode as the first argument to the block] do
          em do
            @zkem.connect do
              @zkem.get(@path) do |exc,*a|
                exc.should be_kind_of(ZK::Exceptions::NoNode)
                @zkem.close! { done }
              end
            end
          end
        end
      end # failure
    end # get

    describe 'create' do
      describe 'success' do
        before do
          @path = [base_path, 'foo'].join('/')
          @zk.delete(@path) rescue ZK::Exceptions::NoNode

          @data = 'this is data'
        end

        describe 'non-sequence node' do
          it 'should create the node and call the callback' do
            em do
              @zkem.connect do
                d = @zkem.create(@path, @data)

                d.callback do |*a| 
                  logger.debug { "got callback with #{a.inspect}" }
                  a.should_not be_empty
                  a.first.should == @path
                  EM.reactor_thread?.should be_true
                  @zkem.close! { done }
                end

                d.errback  do |exc| 
                  raise exc
                end
              end
            end
          end

          it 'should get the data and do a nodejs-style callback' do
            em do
              @zkem.connect do
                @zkem.create(@path, @data) do |exc,created_path|
                  exc.should be_nil
                  created_path.should == @path
                  EM.reactor_thread?.should be_true
                  @zkem.close! { done }
                end
              end
            end
          end
        end # non-sequence node

        describe 'sequence node' do
          it 'should create the node and call the callback' do
            em do
              @zkem.connect do
                d = @zkem.create(@path, @data, :sequence => true)

                d.callback do |*a| 
                  logger.debug { "got callback with #{a.inspect}" }
                  a.should_not be_empty
                  a.first.should =~ /#{@path}\d+$/
                  EM.reactor_thread?.should be_true
                  @zkem.close! { done }
                end

                d.errback  do |exc| 
                  raise exc
                end
              end
            end
          end
        end
      end # success

      describe 'failure' do
        before do
          @path = [base_path, 'foo'].join('/')
          @zk.create(@path, '')
        end

        it %[should call the errback in deferred style] do
          em do
            @zkem.connect do
              d = @zkem.create(@path, '')

              d.callback do
                raise "Should not have been called"
              end

              d.errback do |exc|
                exc.should be_kind_of(ZK::Exceptions::NodeExists)
                @zkem.close! { done }
              end
            end
          end
        end

        it %[should have exception as the first argument to the block] do
          em do
            @zkem.connect do
              @zkem.create(@path, '') do |exc,*a|
                exc.should be_kind_of(ZK::Exceptions::NodeExists)
                @zkem.close! { done }
              end
            end
          end
        end
      end # failure
    end # create

    describe 'set' do
      describe 'success' do
        before do
          @path = [base_path, 'foo'].join('/')
          @data = 'this is data'
          @new_data = 'this is better data'
          @zk.create(@path, @data)
          @orig_stat = @zk.stat(@path)
        end

        it 'should set the data and call the callback' do
          em do
            @zkem.connect do
              dfr = @zkem.set(@path, @new_data)

              dfr.callback do |stat| 
                stat.should be_instance_of(Zookeeper::Stat)
                stat.version.should > @orig_stat.version
                EM.reactor_thread?.should be_true

                @zkem.get(@path) do |_,data|
                  data.should == @new_data
                  @zkem.close! { done }
                end
              end

              dfr.errback  do |exc| 
                raise exc
              end
            end
          end
        end

        it 'should set the data and do a nodejs-style callback' do
          em do
            @zkem.connect do
              @zkem.set(@path, @new_data) do |exc,stat|
                exc.should be_nil
                stat.should be_instance_of(Zookeeper::Stat)
                EM.reactor_thread?.should be_true

                @zkem.get(@path) do |_,data|
                  data.should == @new_data
                  @zkem.close! { done }
                end
              end
            end
          end
        end
      end # success

      describe 'failure' do
        before do
          @path = [base_path, 'foo'].join('/')
          @zk.delete(@path) rescue ZK::Exceptions::NoNode
        end

        it %[should call the errback in deferred style] do
          em do
            @zkem.connect do
              d = @zkem.set(@path, '')

              d.callback do
                raise "Should not have been called"
              end

              d.errback do |exc|
                exc.should be_kind_of(ZK::Exceptions::NoNode)
                @zkem.close! { done }
              end
            end
          end
        end

        it %[should have NoNode as the first argument to the block] do
          em do
            @zkem.connect do
              @zkem.set(@path, '') do |exc,_|
                exc.should be_kind_of(ZK::Exceptions::NoNode)
                @zkem.close! { done }
              end
            end
          end
        end
      end # failure
    end # set

    describe 'exists?' do
      before do
        @path = [base_path, 'foo'].join('/')
        @data = 'this is data'
      end

      it 'should call the block with true if the node exists' do
        @zk.create(@path, @data)

        em do
          @zkem.connect do
            dfr = @zkem.exists?(@path)

            dfr.callback do |bool| 
              bool.should be_true
              @zkem.close! { done }
            end

            dfr.errback  do |exc| 
              raise exc
            end
          end
        end
      end

      it 'should call the block with false if the node does not exist' do
        @zk.delete(@path) rescue ZK::Exceptions::NoNode

        em do
          @zkem.connect do
            dfr = @zkem.exists?(@path)

            dfr.callback do |bool| 
              bool.should be_false
              @zkem.close! { done }
            end

            dfr.errback  do |exc| 
              raise exc
            end
          end
        end
      end
    end

    describe 'stat' do
      describe 'success' do
        before do
          @path = [base_path, 'foo'].join('/')
          @data = 'this is data'
          @zk.create(@path, @data)
          @orig_stat = @zk.stat(@path)
        end

        it 'should get the stat and call the callback' do
          em do
            @zkem.connect do
              dfr = @zkem.stat(@path)

              dfr.callback do |stat| 
                stat.should_not be_nil
                stat.should == @orig_stat
                stat.should be_instance_of(Zookeeper::Stat)
                EM.reactor_thread?.should be_true
                @zkem.close! { done }
              end

              dfr.errback  do |exc| 
                raise exc
              end
            end
          end
        end

        it 'should get the stat and do a nodejs-style callback' do
          em do
            @zkem.connect do
              @zkem.stat(@path) do |exc,stat|
                exc.should be_nil
                stat.should be_instance_of(Zookeeper::Stat)
                EM.reactor_thread?.should be_true
                @zkem.close! { done }
              end
            end
          end
        end
      end # success

      describe 'non-existent node' do
        before do
          @path = [base_path, 'foo'].join('/')
          @zk.delete(@path) rescue ZK::Exceptions::NoNode
        end

        it %[should not be an error to do stat on a non-existent node] do
          em do
            @zkem.connect do
              dfr = @zkem.stat(@path)

              dfr.callback do |stat| 
                stat.should_not be_nil
                stat.exists?.should be_false
                stat.should be_instance_of(Zookeeper::Stat)
                EM.reactor_thread?.should be_true
                @zkem.close! { done }
              end

              dfr.errback  do |exc| 
                raise exc
              end
            end
          end
        end
      end # non-existent node
    end # stat

    describe 'delete' do
      describe 'success' do
        before do
          @path = [base_path, 'foo'].join('/')
          @data = 'this is data'
          @zk.create(@path, @data)
        end

        it 'should delete the node and call the callback' do
          em do
            @zkem.connect do
              d = @zkem.delete(@path)

              d.callback do |*a| 
                a.should be_empty
                EM.reactor_thread?.should be_true
                @zkem.close! { done }
              end

              d.errback do |exc| 
                raise exc
              end
            end
          end
        end

        it 'should delete the znode and do a nodejs-style callback' do
          em do
            @zkem.connect do
              @zkem.delete(@path) do |exc|
                exc.should be_nil
                EM.reactor_thread?.should be_true
                @zkem.close! { done }
              end
            end
          end
        end
      end # success

      describe 'failure' do
        before do
          @path = [base_path, 'foo'].join('/')
          @zk.delete(@path) rescue ZK::Exceptions::NoNode
        end

        it %[should call the errback in deferred style] do
          em do
            @zkem.connect do
              d = @zkem.delete(@path)

              d.callback do
                raise "Should not have been called"
              end

              d.errback do |exc|
                exc.should be_kind_of(ZK::Exceptions::NoNode)
                @zkem.close! { done }
              end
            end
          end
        end

        it %[should have NoNode as the first argument to the block] do
          em do
            @zkem.connect do
              @zkem.delete(@path) do |exc,_|
                exc.should be_kind_of(ZK::Exceptions::NoNode)
                @zkem.close! { done }
              end
            end
          end
        end
      end # failure
    end # delete

    describe 'children' do
      describe 'success' do
        before do
          @path = [base_path, 'foo'].join('/')
          @child_1_path = [@path, 'child_1'].join('/')
          @child_2_path = [@path, 'child_2'].join('/')

          @data = 'this is data'
          @zk.create(@path, @data)
          @zk.create(@child_1_path, '')
          @zk.create(@child_2_path, '')
        end

        it 'should get the children and call the callback' do
          em do
            @zkem.connect do
              d = @zkem.children(@path)

              d.callback do |children,stat| 
                children.should be_kind_of(Array)
                children.length.should == 2
                children.should include('child_1')
                children.should include('child_2')

                stat.should be_instance_of(Zookeeper::Stat)

                EM.reactor_thread?.should be_true
                @zkem.close! { done }
              end

              d.errback  do |exc| 
                raise exc
              end
            end
          end
        end

        it 'should get the children and do a nodejs-style callback' do
          em do
            @zkem.connect do
              @zkem.children(@path) do |exc, children, stat|
                exc.should be_nil
                children.should be_kind_of(Array)
                children.length.should == 2
                children.should include('child_1')
                children.should include('child_2')
                stat.should be_instance_of(Zookeeper::Stat)
                EM.reactor_thread?.should be_true
                @zkem.close! { done }
              end
            end
          end
        end
      end # success

      describe 'failure' do
        before do
          @path = [base_path, 'foo'].join('/')
          @zk.delete(@path) rescue ZK::Exceptions::NoNode
        end

        it %[should call the errback in deferred style] do
          em do
            @zkem.connect do
              d = @zkem.children(@path)

              d.callback do
                raise "Should not have been called"
              end

              d.errback do |exc|
                exc.should be_kind_of(ZK::Exceptions::NoNode)
                @zkem.close! { done }
              end
            end
          end
        end

        it %[should have NoNode as the first argument to the block] do
          em do
            @zkem.connect do
              @zkem.children(@path) do |exc,_|
                exc.should be_kind_of(ZK::Exceptions::NoNode)
                @zkem.close! { done }
              end
            end
          end
        end
      end # failure
    end # children

    describe 'get_acl' do
      describe 'success' do
        before do
          @path = [base_path, 'foo'].join('/')
          @data = 'this is data'
          @zk.create(@path, @data)
        end

        it 'should get the data and call the callback' do
          em do
            @zkem.connect do
              dfr = @zkem.get_acl(@path)

              dfr.callback do |acls,stat| 
                acls.should be_kind_of(Array)
                acls.first.should be_kind_of(Zookeeper::ACLs::ACL)
                stat.should be_instance_of(Zookeeper::Stat)

                EM.reactor_thread?.should be_true
                @zkem.close! { done }
              end

              dfr.errback  do |exc| 
                raise exc
              end
            end
          end
        end

        it 'should get the data and do a nodejs-style callback' do
          em do
            @zkem.connect do
              @zkem.get_acl(@path) do |exc,acls,stat|
                exc.should be_nil
                acls.should be_kind_of(Array)
                acls.first.should be_kind_of(Zookeeper::ACLs::ACL)
                stat.should be_instance_of(Zookeeper::Stat)
                EM.reactor_thread?.should be_true
                @zkem.close! { done }
              end
            end
          end
        end
      end # success

      describe 'failure' do
        before do
          @path = [base_path, 'foo'].join('/')
          @zk.delete(@path) rescue ZK::Exceptions::NoNode
        end

        it %[should call the errback in deferred style] do
          em do
            @zkem.connect do
              d = @zkem.get_acl(@path)

              d.callback do
                raise "Should not have been called"
              end

              d.errback do |exc|
                exc.should be_kind_of(ZK::Exceptions::NoNode)
                @zkem.close! { done }
              end
            end
          end
        end

        it %[should have NoNode as the first argument to the block] do
          em do
            @zkem.connect do
              @zkem.get_acl(@path) do |exc,*a|
                exc.should be_kind_of(ZK::Exceptions::NoNode)
                @zkem.close! { done }
              end
            end
          end
        end
      end # failure
    end # get_acl

    describe 'set_acl' do
      describe 'success' do
        it 'should set the acl and call the callback' 
        it 'should set the acl and do a nodejs-style callback' 
      end # success

      describe 'failure' do
        it %[should call the errback in deferred style] 
        it %[should have NoNode as the first argument to the block] 
      end # failure
    end # set_acl

    describe 'session_id and session_passwd' do
      it %[should return a Fixnum for session_id once connected] do
        em do
          @zkem.session_id.should be_nil

          @zkem.connect do
            @zkem.session_id.should be_kind_of(Fixnum)
            @zkem.close! { done }
          end
        end
      end

      it %[should return a String for session_passwd once connected] do
        em do
          @zkem.session_passwd.should be_nil

          @zkem.connect do
            @zkem.session_passwd.should be_kind_of(String)
            @zkem.close! { done }
          end
        end
      end
    end

    describe 'on_connection_lost' do
      before do
        @path = [base_path, 'foo'].join('/')
        @data = 'this is data'
        @zk.create(@path, @data)
      end

      it %[should be called back if the connection is lost] do
        em do
          @zkem.on_connection_lost do |exc|
            logger.debug { "WIN!" }
            exc.should be_kind_of(ZK::Exceptions::ConnectionLoss)
            @zkem.close! { done }
          end

          @zkem.connect do
            flexmock(@zkem.__send__(:cnx)) do |m|  # ok, this is being a bit naughty with the __send__
              m.should_receive(:get).with(Hash).and_return do |hash|
                logger.debug { "client received :get wtih #{hash.inspect}" }
                @user_cb = hash[:callback]

                EM.next_tick do
                  logger.debug { "calling back user cb with connection loss" }
                  @user_cb.call(:rc => ZK::Exceptions::CONNECTIONLOSS)
                end

                { :rc => Zookeeper::ZOK }
              end
            end

            @zkem.get(@path) do |exc,data|
              exc.should be_kind_of(ZK::Exceptions::ConnectionLoss)
            end
          end
        end
      end

      it %[should be called if we get a session expired event] do
        @zkem.on_connection_lost do |exc|
          logger.debug { "WIN!" }
          exc.should be_kind_of(ZK::Exceptions::ConnectionLoss)
          @zkem.close! { done }
        end

        em do
          @zkem.connect do
            event = event_mock(:connection_loss_event).tap do |ev|
              ev.should_receive(:state).and_return(Zookeeper::ZOO_EXPIRED_SESSION_STATE)
            end

            EM.next_tick { @zkem.event_handler.process(event) }
          end
        end
      end
    end # on_connection_lost

    describe 'on_connected' do
      it %[should be called back when a ZOO_CONNECTED_STATE event is received] do
        em do
          @zkem.on_connected do |event|
            logger.debug { "WIN!" }
            @zkem.close! { done }
          end

          @zkem.connect do
            logger.debug { "we connected" }
          end
        end
      end
    end # on_connected

    describe 'on_connecting' do
      it %[should be called back when a ZOO_CONNECTING_STATE event is received] do
        @zkem.on_connecting do |event|
          logger.debug { "WIN!" }
          @zkem.close! { done }
        end

        em do
          @zkem.connect do
            event = event_mock(:connecting_event).tap do |ev|
              ev.should_receive(:state).and_return(Zookeeper::ZOO_CONNECTING_STATE)
            end

            EM.next_tick { @zkem.event_handler.process(event) }
          end
        end
      end

      it %[should re-register when the hook in the documentation is used] do

        @perform_count = 0

        hook = proc do |ev|
          @zkem.on_connecting(&hook)

          if ev
            @perform_count += 1
          end

          if @perform_count == 2
            @zkem.close! { done }
          end
        end

        em do
          hook.call(nil)

          @zkem.connect do
            event = event_mock(:connecting_event).tap do |ev|
              ev.should_receive(:state).and_return(Zookeeper::ZOO_CONNECTING_STATE)
            end

            2.times { EM.next_tick { @zkem.event_handler.process(event) } }
          end
        end
      end
    end # on_connecting
  end # Client

  describe 'regular' do

    before do
      @zkem = ZK::ZKEventMachine::Client.new('localhost:2181')
      @zk = ZK.new.tap { |z| wait_until { z.connected? } }
      @zk.should be_connected
    end

    it_should_behave_like 'Client'
  end

  describe 'chrooted' do
    let(:chroot_path) { '/_zkem_chroot_' }
    let(:zk_connect_host) { "localhost:2181#{chroot_path}" }

    before :all do
      ZK.open('localhost:2181') do |z|
        z.rm_rf(chroot_path)
        z.mkdir_p(chroot_path)
      end
    end

    after :all do
      ZK.open('localhost:2181') do |z|
        z.rm_rf(chroot_path)
      end
    end

    before do
      @zkem = ZK::ZKEventMachine::Client.new(zk_connect_host)
      @zk = ZK.new(zk_connect_host).tap { |z| wait_until { z.connected? } }
      @zk.should be_connected
    end

    it_should_behave_like 'Client'
  end
end # ZK::ZKEventMachine

