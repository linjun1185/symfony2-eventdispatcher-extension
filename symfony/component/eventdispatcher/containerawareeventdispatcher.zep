namespace Symfony\Component\EventDispatcher;

/**
 * Lazily loads listeners and subscribers from the dependency injection
 * container
 *
 * @author Fabien Potencier <fabien@symfony.com>
 * @author Bernhard Schussek <bschussek@gmail.com>
 * @author Jordan Alliot <jordan.alliot@gmail.com>
 * @author Damien Alexandre <dalexandre@jolicode.com>
 */
class ContainerAwareEventDispatcher extends \Symfony\Component\EventDispatcher\EventDispatcher
{
    /**
     * The container from where services are loaded
     * @var ContainerInterface
     */
    private $container;

    /**
     * The service IDs of the event listeners and subscribers
     * @var array
     */
    private $listenerIds;

    /**
     * The services registered as listeners - renamed for Zephir private handling
     * @var array
     */
    protected $listeners_container;

    /**
     * Constructor.
     *
     * @param ContainerInterface $container A ContainerInterface instance
     */
    public function __construct(<\Symfony\Component\DependencyInjection\ContainerInterface> $container)
    {
        parent::__construct(); // Needed for Zephir init as array

        let $this->listeners_container = [];
        let $this->container   = $container;
        let $this->listenerIds = [];
    }

    /**
     * Adds a service as event listener
     *
     * @param string $eventName Event for which the listener is added
     * @param array  $callback  The service ID of the listener service & the method
     *                            name that has to be called
     * @param integer $priority The higher this value, the earlier an event listener
     *                            will be triggered in the chain.
     *                            Defaults to 0.
     *
     * @throws \InvalidArgumentException
     */
    public function addListenerService(string $eventName, $callback, long $priority = 0) -> void
    {
        var $listener_service;

        if (typeof $callback != "array" || count($callback) !== 2) {
            throw new \InvalidArgumentException("Expected an array(\"service\", \"method\") argument");
        }

        if !isset $this->listenerIds[$eventName] {
            let $this->listenerIds[$eventName] = [];
        }

        let $listener_service   = $this->listenerIds[$eventName];
        let $listener_service[] = [$callback[0], $callback[1], $priority];
        let $this->listenerIds[$eventName] = $listener_service;
    }

    public function removeListener($eventName, $listener)
    {
        var $key, $l, $i, $args, $priority, $method, $serviceId;

        $this->lazyLoad($eventName);

        if isset $this->listeners_container[$eventName] {
            for $key, $l in $this->listeners_container[$eventName] {
                for $i, $args in $this->listenerIds[$eventName] {

                    let $serviceId = $args[0];
                    let $method    = $args[1];
                    let $priority  = $args[2];

                    if ($key === sprintf("%s.%s", $serviceId, $method)) {
                        if ($listener[0] === $l && $listener[1] === $method) {
                            unset $this->listeners_container[$eventName][$key];
                            if (empty($this->listeners_container[$eventName])) {
                                unset $this->listeners_container[$eventName];
                            }

                            unset $this->listenerIds[$eventName][$i];
                            if (empty($this->listenerIds[$eventName])) {
                                unset $this->listenerIds[$eventName];
                            }
                        }
                    }
                }
            }
        }

        parent::removeListener($eventName, $listener);
    }

    /**
     * @see EventDispatcherInterface::hasListeners
     */
    public function hasListeners($eventName = null) -> boolean
    {
        if ($eventName === null) {
            return count($this->listenerIds) > 0 || count($this->listeners_container) > 0;
        }

        if isset $this->listenerIds[$eventName] {
            return true;
        }

        return parent::hasListeners($eventName);
    }

    /**
     * @see EventDispatcherInterface::getListeners
     */
    public function getListeners($eventName = null)
    {
        var $serviceEventName, $serviceEvent;

        if ($eventName === null) {
            for $serviceEventName, $serviceEvent in $this->listenerIds {
                $this->lazyLoad($serviceEventName);
            }
        } else {
            $this->lazyLoad($eventName);
        }

        return parent::getListeners($eventName);
    }

    /**
     * Adds a service as event subscriber
     *
     * @param string $serviceId The service ID of the subscriber service
     * @param string $class     The service's class name (which must implement EventSubscriberInterface)
     */
    public function addSubscriberService(string! $serviceId, string! $class)
    {
        var $eventName, $params, $listener, $event, $events;

        let $events = call_user_func(sprintf("%s::getSubscribedEvents", $class));

        for $eventName, $params in $events {
            if (is_string($params)) {
                let $event = isset $this->listenerIds[$eventName] ? $this->listenerIds[$eventName] : [];
                let $event[] = [$serviceId, $params, 0];
                let $this->listenerIds[$eventName] = $event;
            } else {
                if (is_string($params[0])) {
                    let $event = isset $this->listenerIds[$eventName] ? $this->listenerIds[$eventName] : [];
                    let $event[] = [$serviceId, $params[0], (isset $params[1] ? $params[1] : 0)];
                    let $this->listenerIds[$eventName] = $event;
                } else {
                    for $listener in $params {
                        let $event = isset $this->listenerIds[$eventName] ? $this->listenerIds[$eventName] : [];
                        let $event[] = [$serviceId, $listener[0], (isset $listener[1] ? $listener[1] : 0)];
                        let $this->listenerIds[$eventName] = $event;
                    }
                }
            }
        }
    }

    /**
     * {@inheritDoc}
     *
     * Lazily loads listeners for this event from the dependency injection
     * container.
     *
     * @throws \InvalidArgumentException if the service is not defined
     */
    public function dispatch(string! $eventName, <\Symfony\Component\EventDispatcher\Event> $event = null)
    {
        $this->lazyLoad($eventName);

        return parent::dispatch($eventName, $event);
    }

    public function getContainer()
    {
        return $this->container;
    }

    /**
     * Lazily loads listeners for this event from the dependency injection
     * container.
     *
     * @param string $eventName The name of the event to dispatch. The name of
     *                          the event is the name of the method that is
     *                          invoked on listeners.
     */
    protected function lazyLoad(string! $eventName) -> void
    {
        var $serviceId, $method, $priority, $args, $listener, $key, $callback;

        if isset $this->listenerIds[$eventName] {
            for $args in $this->listenerIds[$eventName] {
                let $serviceId = $args[0];
                let $method    = $args[1];
                let $priority  = $args[2];
                let $listener  = $this->container->get($serviceId);
                let $key       = $serviceId.".".$method;
                let $callback  = [$listener, $method];

                if !isset $this->listeners_container[$eventName] || !isset $this->listeners_container[$eventName][$key] {
                    $this->addListener($eventName, $callback, $priority);
                } else {
                    if $listener !== $this->listeners_container[$eventName][$key] {
                        parent::removeListener($eventName, [$this->listeners_container[$eventName][$key], $method]);
                        $this->addListener($eventName, $callback, $priority);
                    }
                }

                let $this->listeners_container[$eventName][$key] = $listener;
            }
        }
    }
}